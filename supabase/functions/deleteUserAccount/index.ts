import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseAdmin = createSupabaseAdminClient()

    // ─── Obter userId do body ─────────────────────────────────────────────────
    // O Edge Runtime já validou o JWT (vemos isso nos logs com auth_user)
    // Se chegou até aqui, o usuário está autenticado
    const body = await req.json().catch(() => ({}))
    const userId = body?.userId as string | null

    if (!userId) {
      return new Response(
        JSON.stringify({ error: 'userId não fornecido no body da requisição' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`[deleteUserAccount] Iniciando exclusão para userId: ${userId}`)

    // ─── 1. Buscar lojas do usuário ───────────────────────────────────────────
    const { data: shops, error: shopsError } = await supabaseAdmin
      .from('shops')
      .select('id')
      .eq('owner_id', userId)

    if (shopsError) {
      throw new Error(`Erro ao buscar lojas: ${shopsError.message}`)
    }

    // ─── 2. Apagar dados das lojas em paralelo ────────────────────────────────
    if (shops && shops.length > 0) {
      console.log(`[deleteUserAccount] ${shops.length} loja(s) encontrada(s). Limpando...`)
      await Promise.all(shops.map(async (shop) => {
        const shopId = shop.id
        // Apagar dependências da loja em paralelo
        await Promise.all([
          supabaseAdmin.from('appointments').delete().eq('shop_id', shopId),
          supabaseAdmin.from('services').delete().eq('shop_id', shopId),
          supabaseAdmin.from('employees').delete().eq('shop_id', shopId),
          supabaseAdmin.from('products').delete().eq('shop_id', shopId),
          supabaseAdmin.from('coupons').delete().eq('shop_id', shopId),
        ])
        // Apagar a loja após limpar suas dependências
        await supabaseAdmin.from('shops').delete().eq('id', shopId)
      }))
    }

    // ─── 3. Apagar dados do usuário como Cliente (em paralelo) ───────────────
    await Promise.all([
      supabaseAdmin.from('appointments').delete().eq('client_id', userId),
      supabaseAdmin.from('coupon_usage').delete().eq('user_id', userId),
      supabaseAdmin.from('favorites').delete().eq('user_id', userId),
    ])

    // ─── 4. Apagar perfil na tabela users ────────────────────────────────────
    await supabaseAdmin.from('users').delete().eq('id', userId)

    // ─── 5. Apagar do Supabase Auth (cascata: shop_clients, shop_views, affiliates) ─
    const { error: deleteAuthError } = await supabaseAdmin.auth.admin.deleteUser(userId)
    if (deleteAuthError) {
      throw new Error(`Erro ao excluir do Auth: ${deleteAuthError.message}`)
    }

    console.log(`[deleteUserAccount] ✅ Conta ${userId} excluída com sucesso!`)

    return new Response(
      JSON.stringify({ success: true, message: 'Conta excluída com sucesso' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error(`[deleteUserAccount] Erro:`, error instanceof Error ? error.message : String(error))
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Erro interno ao excluir conta' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
