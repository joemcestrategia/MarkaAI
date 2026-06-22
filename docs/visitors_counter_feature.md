# Implementação: Contador de Visitantes na Aba

## Funcionalidade Adicionada
Bolinha com contador acima do botão "Visitantes" mostrando o número total de visitantes que visualizaram a loja.

## Objetivos
- ✅ Mostrar número de visitantes mesmo para planos gratuitos
- ✅ Incentivar upgrade de plano ao mostrar leads perdidos
- ✅ Fornecer métrica útil para o negócio

## Implementação

### 1. Variáveis de Estado
**Arquivo:** `lib/modules/business/business_clients_page.dart`  
**Linhas:** 46-48

```dart
// --- Contadores para as abas ---
int _visitorsCount = 0;
int _clientsCount = 0;
```

### 2. Função _buildTabButton Modificada
**Linhas:** 841-920

- Adicionado parâmetro `count?: int`
- Implementado `Stack` para sobrepor a bolinha do contador
- Lógica para mostrar "99+" quando count > 99
- Posicionamento da bolinha no canto superior direito

**Design da Bolinha:**
- Cor: Vermelho (`Colors.red`)
- Borda: Branca (`Colors.white`, width: 1.5)
- Formato: Arredondado (`BorderRadius.circular(10)`)
- Texto: Branco, negrito, tamanho 10

### 3. Atualização dos Contadores
**Linhas:** 519-529

```dart
// Extrair contadores
final int visitorsCount = _cachedData!['visitors']!.length;
final int clientsCount = _cachedData!['clients']!.length;

// Atualizar contadores das abas
if (mounted) {
  setState(() {
    _visitorsCount = visitorsCount;
    _clientsCount = clientsCount;
  });
}
```

### 4. Atualização das Chamadas dos Botões
**Linhas:** 448-452

```dart
_buildTabButton(0, "Clientes", Icons.people_outline, count: _clientsCount),
_buildTabButton(1, "Visitantes", Icons.visibility_outlined, 
    isLocked: !_currentFeatures.automationClientSawNoBook, 
    count: _visitorsCount),
```

## Comportamento

### Para Planos Gratuitos
- ✅ Bolinha vermelha aparece acima do botão "Visitantes"
- ✅ Botão permanece bloqueado (ícone de cadeado)
- ✅ Contador visível mesmo sem acesso à aba

### Para Planos Plus/Pagos
- ✅ Bolinha vermelha aparece acima do botão "Visitantes"
- ✅ Botão desbloqueado e funcional
- ✅ Contador atualizado em tempo real

### Design Responsivo
- ✅ Bolinha se adapta a diferentes tamanhos de tela
- ✅ Texto "99+" para números grandes
- ✅ Não interfere na usabilidade dos botões

## Validação
- ✅ Compilação sem erros (`flutter analyze`)
- ✅ Contadores atualizados via StreamBuilder
- ✅ Proteção contra setState após dispose
- ✅ Funciona para todos os planos

## Impacto de Negócio
1. **Visibilidade**: Donos veem quantos leads estão perdendo
2. **Incentivo**: Motiva upgrade para acessar dados de visitantes
3. **Métrica**: Fornece KPI importante para o negócio
4. **Conversão**: Aumenta probabilidade de upgrade de plano

## Exemplo Visual
```
[Clientes] [Visitantes●]
           ↑
         15
```

Onde ● é a bolinha vermelha com o número "15".
