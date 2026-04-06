# Correção: setState() Durante Build

## Problema
```
FlutterError (setState() or markNeedsBuild() called during build.
This BusinessClientsScreen widget cannot be marked as needing to build because the framework is already in the process of building widgets.
```

## Causa
O `setState()` estava sendo chamado diretamente dentro do `builder` do StreamBuilder, o que não é permitido pelo Flutter durante a fase de construção da UI.

## Solução
Usar `WidgetsBinding.instance.addPostFrameCallback` para agendar o `setState()` após o ciclo de build atual.

### Código Antigo (Linhas 525-532)
```dart
// Atualizar contadores das abas
if (mounted) {
  setState(() {
    _visitorsCount = visitorsCount;
    _clientsCount = clientsCount;
  });
}
```

### Código Novo
```dart
// Atualizar contadores das abas (após o build)
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted) {
    setState(() {
      _visitorsCount = visitorsCount;
      _clientsCount = clientsCount;
    });
  }
});
```

## Explicação
- `addPostFrameCallback` agenda a execução para após o frame atual ser completado
- Evita o erro de chamada de `setState()` durante o build
- Mantém a funcionalidade de atualizar os contadores
- Preserva a verificação de `mounted` para evitar leaks

## Validação
- ✅ Compilação sem erros
- ✅ Funcionalidade mantida
- ✅ Sem crashes durante o build

## Status
**RESOLVIDO** - O app não trava mais e os contadores são atualizados corretamente.
