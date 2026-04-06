import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'
import { corsHeaders } from '../_shared/cors.ts'

// ==========================================
// VAPID Web Push Implementation (P-256 / ES256)
// ==========================================

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
  const rawData = atob(base64)
  const output = new Uint8Array(rawData.length)
  for (let i = 0; i < rawData.length; ++i) {
    output[i] = rawData.charCodeAt(i)
  }
  return output
}

function uint8ArrayToBase64Url(arr: Uint8Array): string {
  let binary = ''
  arr.forEach((b) => (binary += String.fromCharCode(b)))
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

async function buildVapidJwt(audience: string, subject: string, privateKeyRaw: Uint8Array): Promise<string> {
  const header  = uint8ArrayToBase64Url(new TextEncoder().encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })))
  const payload = uint8ArrayToBase64Url(new TextEncoder().encode(JSON.stringify({
    aud: audience,
    exp: Math.floor(Date.now() / 1000) + 12 * 3600,
    sub: subject,
  })))

  const signingInput = `${header}.${payload}`

  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    privateKeyRaw,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  )

  const signatureBuffer = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    cryptoKey,
    new TextEncoder().encode(signingInput)
  )

  return `${signingInput}.${uint8ArrayToBase64Url(new Uint8Array(signatureBuffer))}`
}

// Encrypts the push notification payload using ECDH + HKDF + AES-128-GCM (RFC 8291 / RFC 8188)
async function encryptPayload(
  subscriptionPublicKeyBase64Url: string,
  authBase64Url: string,
  plaintext: string
): Promise<{ ciphertext: Uint8Array; salt: Uint8Array; serverPublicKey: Uint8Array }> {
  const encoder = new TextEncoder()
  const plaintextBytes = encoder.encode(plaintext)

  // Generate ephemeral key pair for ECDH
  const serverKeyPair = await crypto.subtle.generateKey(
    { name: 'ECDH', namedCurve: 'P-256' },
    true,
    ['deriveBits']
  )

  // Import recipient public key
  const recipientPublicKeyBytes = urlBase64ToUint8Array(subscriptionPublicKeyBase64Url)
  const recipientPublicKey = await crypto.subtle.importKey(
    'raw',
    recipientPublicKeyBytes,
    { name: 'ECDH', namedCurve: 'P-256' },
    false,
    []
  )

  // ECDH shared secret
  const sharedSecret = await crypto.subtle.deriveBits(
    { name: 'ECDH', public: recipientPublicKey },
    serverKeyPair.privateKey,
    256
  )

  // Export server public key (uncompressed, 65 bytes)
  const serverPublicKeyRaw = new Uint8Array(await crypto.subtle.exportKey('raw', serverKeyPair.publicKey))

  // Random salt
  const salt = crypto.getRandomValues(new Uint8Array(16))

  // Auth secret (from subscription)
  const authSecret = urlBase64ToUint8Array(authBase64Url)

  // HKDF to derive content encryption key and nonce
  const prk = await hkdf('SHA-256', new Uint8Array(sharedSecret), authSecret,
    concat(encoder.encode('WebPush: info\0'), recipientPublicKeyBytes, serverPublicKeyRaw), 32)

  const contentEncryptionKey = await hkdf('SHA-256', prk, salt,
    encoder.encode('Content-Encoding: aes128gcm\0'), 16)

  const nonce = await hkdf('SHA-256', prk, salt,
    encoder.encode('Content-Encoding: nonce\0'), 12)

  // Import AES-128-GCM key
  const aesKey = await crypto.subtle.importKey('raw', contentEncryptionKey, 'AES-GCM', false, ['encrypt'])

  // Pad plaintext to 4096 bytes (RFC 8291 §4)
  const recordSize = 4096
  // payload = plaintext + 0x02 delimiter + padding (zeros)
  const padded = new Uint8Array(recordSize)
  padded.set(plaintextBytes)
  padded[plaintextBytes.length] = 0x02 // delimiter

  const encryptedContent = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce },
    aesKey,
    padded
  )

  // Build the aes128gcm content-coding header (RFC 8188 §2.1)
  // salt (16) + recordSize (4, BE uint32) + keyIdLength (1) + keyId (65 bytes = server public key)
  const header = new Uint8Array(16 + 4 + 1 + 65)
  header.set(salt, 0)
  const view = new DataView(header.buffer)
  view.setUint32(16, recordSize + 16, false) // record_size = content + GCM tag (16 bytes)
  header[20] = 65 // key_id_len
  header.set(serverPublicKeyRaw, 21)

  const ciphertext = concat(header, new Uint8Array(encryptedContent))
  return { ciphertext, salt, serverPublicKey: serverPublicKeyRaw }
}

async function hkdf(
  hash: string,
  ikm: Uint8Array,
  salt: Uint8Array,
  info: Uint8Array,
  length: number
): Promise<Uint8Array> {
  const keyMaterial = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits'])
  const bits = await crypto.subtle.deriveBits(
    { name: 'HKDF', hash, salt, info },
    keyMaterial,
    length * 8
  )
  return new Uint8Array(bits)
}

function concat(...arrays: Uint8Array[]): Uint8Array {
  const total = arrays.reduce((acc, a) => acc + a.length, 0)
  const result = new Uint8Array(total)
  let offset = 0
  for (const arr of arrays) {
    result.set(arr, offset)
    offset += arr.length
  }
  return result
}

// ==========================================
// Send Web Push to a single subscription
// ==========================================

async function sendWebPush(subscription: {
  endpoint: string
  p256dh: string
  auth_key: string
}, payload: string): Promise<boolean> {
  const vapidPublicKey  = Deno.env.get('VAPID_PUBLIC_KEY')
  const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY')
  const vapidSubject    = Deno.env.get('VAPID_SUBJECT') || 'mailto:no-reply@markaai.com.br'

  if (!vapidPublicKey || !vapidPrivateKey) {
    console.error('[sendWebPush] VAPID_PUBLIC_KEY ou VAPID_PRIVATE_KEY não configurados.')
    return false
  }

  try {
    const url = new URL(subscription.endpoint)
    const audience = `${url.protocol}//${url.host}`

    const privateKeyBytes = urlBase64ToUint8Array(vapidPrivateKey)
    const jwt = await buildVapidJwt(audience, vapidSubject, privateKeyBytes)

    const { ciphertext } = await encryptPayload(subscription.p256dh, subscription.auth_key, payload)

    const response = await fetch(subscription.endpoint, {
      method: 'POST',
      headers: {
        'Authorization': `vapid t=${jwt},k=${vapidPublicKey}`,
        'Content-Encoding': 'aes128gcm',
        'Content-Type': 'application/octet-stream',
        'TTL': '86400',
      },
      body: ciphertext,
    })

    if (response.status === 410 || response.status === 404) {
      // Subscription expired / invalid - caller should delete it
      return false
    }

    if (!response.ok) {
      const text = await response.text()
      console.error(`[sendWebPush] Push falhou (${response.status}):`, text)
      return false
    }

    return true
  } catch (err) {
    console.error('[sendWebPush] Erro:', err)
    return false
  }
}

// ==========================================
// HTTP Handler
// ==========================================

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const body = await req.json()
    const { user_id, title, message, data: payloadData } = body

    if (!user_id || !title) {
      return new Response(
        JSON.stringify({ error: 'user_id e title são obrigatórios' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabase = createSupabaseAdminClient()

    // Buscar todas as subscriptions do usuário
    const { data: subscriptions, error } = await supabase
      .from('push_subscriptions')
      .select('id, endpoint, p256dh, auth_key')
      .eq('user_id', user_id)

    if (error) throw error
    if (!subscriptions || subscriptions.length === 0) {
      return new Response(
        JSON.stringify({ success: true, sent: 0, message: 'Sem subscriptions registradas' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const notificationPayload = JSON.stringify({
      title,
      body: message || '',
      data: payloadData || {},
    })

    let sent = 0
    const toDelete: string[] = []

    for (const sub of subscriptions) {
      const ok = await sendWebPush(sub, notificationPayload)
      if (ok) {
        sent++
      } else {
        toDelete.push(sub.id)
      }
    }

    // Remove subscriptions inválidas/expiradas
    if (toDelete.length > 0) {
      await supabase.from('push_subscriptions').delete().in('id', toDelete)
      console.log(`[sendPushNotification] ${toDelete.length} subscription(s) removida(s) por expiração`)
    }

    return new Response(
      JSON.stringify({ success: true, sent, total: subscriptions.length }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('[sendPushNotification] Erro:', err)
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
