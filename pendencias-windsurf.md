# PENDÊNCIAS PARA AGENTES WINDSURF
Gerado em: 2026-03-24 08:30
Resolvido pelo Orquestrador: 0 subtarefas (Modo "só mapeia")
Pendente para Windsurf: 4 subtarefas

---

## CONTEXTO GERAL
Foi realizada uma auditoria completa no projeto (Flutter/Dart e Banco de Dados). 
Não foram encontrados erros de compilação críticos (quebras de imports), mas há 147 avisos de linting, depreciações e boas práticas.
O banco de dados (Supabase) possui schema estruturado, mas há referências legadas (como `firebase_uid`).

## ESTADO ATUAL DO PROJETO
- **O que já foi corrigido:** N/A (Modo Leitura)
- **O que ainda precisa de atenção:** Depreciações de pacotes (`Share`, `FormFields`), Avisos de `BuildContext` em gaps assíncronos.
- **Arquivos modificados:** Nenhum.

---

## TAREFA-001 — Atualizar Depreciações de Pacotes (Flutter)
**Prioridade:** MÉDIA
**Por que não foi resolvida aqui:** Modo "só mapeia" ativado pelo usuário.
**Arquivos envolvidos:** `lib/core/services/coupon_share_service.dart`, `lib/modules/admin/admin_simple_page.dart`, `lib/modules/business/boost_shop_page.dart`, etc.
**Dependências:** Nenhuma.

**Contexto para o agente:**
Existem várias depreciações devido a atualizações do Flutter/Dart:
1. `Share` -> Usar `SharePlus`.
2. `.withOpacity` -> Usar `.withValues()`.
3. `value` em FormFields -> Usar `initialValue`.
4. `groupValue`/`onChanged` em Radio -> Usar `RadioGroup`.

**O que fazer:**
1. Pesquisar por `deprecated_member_use` nos arquivos e substituir pelas APIs atuais.
2. Testar se o comportamento visual/fluxo continua o mesmo.

**Critério de conclusão:**
- [ ] `flutter analyze` não deve reportar avisos de `deprecated_member_use` nos arquivos editados.

---

## TAREFA-002 — Correção de Boas Práticas (Async Gaps e BuildContext)
**Prioridade:** BAIXA
**Por que não foi resolvida aqui:** Alterações extensas e repetitivas (Modo "só mapeia").
**Arquivos envolvidos:** `lib/modules/business/business_schedule_page.dart`, `lib/modules/clients/address_selector_page.dart`, etc.

**Contexto para o agente:**
Existem múltiplos avisos de `use_build_context_synchronously`. O contexto está sendo acessado após operações assíncronas sem verificar `mounted`.

**O que fazer:**
1. Adicionar `if (!mounted) return;` antes de usar `BuildContext` após `await`.

**Critério de conclusão:**
- [ ] Remoção dos avisos `use_build_context_synchronously` nos arquivos editados.

---

## TAREFA-003 — Configuração de Google Places API (Chave de API)
**Prioridade:** CRÍTICA
**Por que não foi resolvida aqui:** Exige dados de ambiente dinâmicos (credenciais do usuário).
**Arquivos envolvidos:** `LEIA-ME_URGENTE.md`, `functions/.env.local` (se aplicável).

**Contexto para o agente:**
O arquivo `LEIA-ME_URGENTE.md` indica que a **Google Places API Key** não está configurada, gerando erro 500 no backend.

**O que fazer:**
1. Garantir que o usuário configurou a chave no ambiente local de `functions/.env`.
2. Auxiliar no deploy: `firebase deploy --only functions`.

**Critério de conclusão:**
- [ ] Chave configurada e deploy executado.

---

## TAREFA-004 — Limpeza de Colunas Legadas no Banco
**Prioridade:** BAIXA
**Por que não foi resolvida aqui:** Modo "só mapeia".
**Arquivos envolvidos:** `comprehensive_schema.json` (tabela `shops`).

**Contexto para o agente:**
A tabela `shops` possui a coluna `firebase_uid`. É recomendável verificar se ela ainda é necessária ou se pode ser removida (já que a migração para Supabase foi concluída).

**O que fazer:**
1. Auditar referências a `firebase_uid` no código Flutter.
2. Se não houver, propor remoção da coluna.

**Critério de conclusão:**
- [ ] Diagnóstico da coluna concluído.

---

## ORDEM DE EXECUÇÃO RECOMENDADA
1. TAREFA-003 (Crítica para funcionamento de conexões)
2. TAREFA-001 (Limpar código)
3. TAREFA-002
4. TAREFA-004

## VALIDAÇÃO FINAL
Após todas as tarefas, rode:
[ ] `flutter analyze`
[ ] Teste de conexão Google Places no Dashboard
