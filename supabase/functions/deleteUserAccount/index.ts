import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseAdmin = createSupabaseAdminClient()

    // Obter o userId enviado no body pelo Flutter
    let userId: string | null = null
    try {
      const body = await req.json()
      userId = body?.userId ?? null
    } catch (_) {
      // body vazio ou inválido
    }

    if (!userId) {
      return new Response(
        JSON.stringify({ error: 'userId não fornecido no body da requisição' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validar que o usuário existe no Supabase Auth (segurança via Service Role)
    const { data: authUserData, error: authLookupError } = await supabaseAdmin.auth.admin.getUserById(userId)
    if (authLookupError || !authUserData?.user) {
      return new Response(
        JSON.stringify({ error: 'Usuário não encontrado no sistema de autenticação' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`[PASS_TRACK] Iniciando exclusão para userId: ${userId}`)
    let currentStep = 'Início'

    // Helper para forçar timeout em promessas
    const withTimeout = <T>(promise: Promise<T>, ms: number, stepName: string): Promise<T> => {
      return Promise.race([
        promise,
        new Promise<T>((_, reject) =>
          setTimeout(() => reject(new Error(`Timeout de ${ms}ms no passo [${stepName}]`)), ms)
        )
      ]);
    };

    // Helper para deletar com tolerância a tabela vazia (sem registros)
    const safeDelete = async (table: string, column: string, value: string, stepName: string) => {
      currentStep = stepName
      console.log(`[PASS_TRACK] → ${stepName}`)
      const { error } = (await withTimeout(
        supabaseAdmin.from(table).delete().eq(column, value),
        12000,
        stepName
      )) as any
      if (error) {
        // Ignoramos "no rows" pois é esperado em contas sem dados
        const msg = error.message ?? ''
        if (!msg.includes('no rows') && !msg.includes('0 rows')) {
          throw new Error(`Erro em [${stepName}]: ${msg}`)
        }
      }
    }

    // 1. Buscar lojas de qual o usuário é dono
    currentStep = 'Buscar Lojas'
    console.log(`[PASS_TRACK] → Buscando lojas...`)
    const { data: shops, error: shopsError } = (await withTimeout(
      supabaseAdmin.from('shops').select('id').eq('owner_id', userId),
      12000,
      currentStep
    )) as any

    if (shopsError) {
      throw new Error(`Erro ao buscar lojas: ${shopsError.message}`)
    }

    // 2. Apagar dados dependentes das lojas
    if (shops && shops.length > 0) {
      console.log(`[PASS_TRACK] Encontradas ${shops.length} loja(s). Limpando...`)
      for (const shop of shops) {
        const shopId = shop.id
        await safeDelete('appointments', 'shop_id', shopId, `Apagar Agendamentos da Loja ${shopId}`)
        await safeDelete('services', 'shop_id', shopId, `Apagar Serviços da Loja ${shopId}`)
        await safeDelete('employees', 'shop_id', shopId, `Apagar Funcionários da Loja ${shopId}`)
        await safeDelete('products', 'shop_id', shopId, `Apagar Produtos da Loja ${shopId}`)
        await safeDelete('shops', 'id', shopId, `Apagar Loja ${shopId}`)
      }
    } else {
      console.log(`[PASS_TRACK] Nenhuma loja vinculada.`)
    }

    // 3. Apagar dados do usuário como Cliente
    await safeDelete('appointments', 'client_id', userId, 'Apagar Agendamentos do Cliente')

    // 4. Apagar perfil na tabela users
    await safeDelete('users', 'id', userId, 'Apagar Perfil do Usuário')

    // 5. Apagar do Supabase Auth (deve ser o último passo)
    currentStep = 'Apagar do Supabase Auth'
    console.log(`[PASS_TRACK] → Apagando do Auth...`)
    const { error: deleteAuthError } = (await withTimeout(
      supabaseAdmin.auth.admin.deleteUser(userId),
      15000,
      currentStep
    )) as any
    if (deleteAuthError) {
      throw new Error(`Erro ao excluir do Auth: ${deleteAuthError.message}`)
    }

    console.log(`[PASS_TRACK] ✅ Conta ${userId} excluída com sucesso!`)

    return new Response(
      JSON.stringify({ success: true, message: 'Conta excluída com sucesso' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error(`[ERRO] Passo que falhou: ${error instanceof Error ? error.message : String(error)}`)
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Erro interno ao excluir conta' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
