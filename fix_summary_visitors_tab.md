# Correção da Aba de Visitantes - Business Clients Page

## Problema Original
A aba de "Visitantes" estava mostrando apenas "Cliente interesse" porque a lógica de separação estava movendo visitantes que favoritaram a loja para a lista de clientes.

## Causa Raiz
Na lógica original (linhas 794-798), um visitante era movido para a lista de clientes se:
- Tivesse agendamentos (`c['agendamentosCount'] > 0`) **OU**
- Tivesse favoritado a loja (`c['isFavorite'] == true`)

Isso fazia com que visitantes que apenas favoritaram a loja fossem classificados incorretamente como "clientes".

## Solução Aplicada
Modificada a lógica para:
- **Clientes**: Apenas quem tem `agendamentosCount > 0`
- **Visitantes**: Quem não tem agendamentos (independente de ter favoritado ou apenas visualizado)

### Código Anterior:
```dart
if (c['agendamentosCount'] > 0 || c['isFavorite'] == true) {
  mainClients.add(c);
} else if (c['isVisitor'] == true) {
  visitorLeads.add(c);
}
```

### Código Novo:
```dart
if (c['agendamentosCount'] > 0) {
  mainClients.add(c);
} else {
  visitorLeads.add(c);
}
```

## Resultado Esperado
Agora a aba "Visitantes" deve mostrar corretamente:
1. Usuários que visualizaram a loja (`shop_views`)
2. Usuários que favoritaram a loja (`favorites`)
3. Mas que **não** possuem agendamentos registrados

## Validação
- ✅ Arquivo compilando sem erros (`flutter analyze`)
- ✅ Lógica simplificada e mais intuitiva
- ✅ Scripts SQL criados para testar dados no banco

## Scripts de Teste
- `debug_shop_views.sql` - Verificar dados no banco
- `test_visitors_logic.sql` - Simular lógica de separação

Execute os scripts SQL no Supabase Dashboard para validar com seus dados reais.
