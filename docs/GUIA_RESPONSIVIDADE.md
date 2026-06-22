# 📱💻 Guia de Responsividade - MarkaAI

Este guia documenta como corrigir problemas de responsividade no app.

## 🎯 Objetivos

1. **Mobile**: Telas sempre full-screen, sem modais (usar navegação)
2. **Desktop**: Largura máxima de 1200px, conteúdo centralizado
3. **Sem overflows**: Corrigir barras amarelas no mobile

## 🛠️ Helper Criado: `ResponsiveHelper`

Localização: `lib/core/utils/responsive_helper.dart`

### Métodos Disponíveis:

```dart
// Verificar dispositivo
ResponsiveHelper.isMobile(context)    // < 600px
ResponsiveHelper.isTablet(context)    // 600-1024px
ResponsiveHelper.isDesktop(context)   // >= 1024px

// Largura máxima para desktop
ResponsiveHelper.getMaxContentWidth(context) // 1200px

// Padding responsivo
ResponsiveHelper.getPagePadding(context)

// Modal responsivo (mobile = página, desktop = modal)
ResponsiveHelper.showResponsiveDialog(
  context: context,
  builder: (context) => MinhaWidget(),
)

// Bottom sheet responsivo
ResponsiveHelper.showResponsiveBottomSheet(
  context: context,
  builder: (context) => MinhaWidget(),
)

// Centralizar conteúdo no desktop
ResponsiveHelper.centerContentOnDesktop(
  context: context,
  child: MinhaWidget(),
)

// Scaffold com largura máxima
ResponsiveHelper.responsiveScaffold(
  context: context,
  appBar: AppBar(...),
  body: MeuConteudo(),
)
```

## 🔧 Como Corrigir Páginas

### 1. Substituir `showDialog` por `showResponsiveDialog`

**ANTES:**
```dart
showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('Título'),
    content: Text('Conteúdo'),
  ),
);
```

**DEPOIS:**
```dart
ResponsiveHelper.showResponsiveDialog(
  context: context,
  builder: (context) => Scaffold(
    appBar: AppBar(
      title: Text('Título'),
      leading: IconButton(
        icon: Icon(Icons.close),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: Text('Conteúdo'),
  ),
);
```

### 2. Limitar Largura no Desktop

**ANTES:**
```dart
Scaffold(
  body: Container(
    width: double.infinity, // Muito largo no desktop!
    child: MeuConteudo(),
  ),
)
```

**DEPOIS:**
```dart
ResponsiveHelper.responsiveScaffold(
  context: context,
  appBar: AppBar(...),
  body: MeuConteudo(),
)
```

### 3. Corrigir Overflows no Mobile

**PROBLEMA COMUM:**
```dart
Row(
  children: [
    Text('Texto muito longo que não cabe'),
    Text('Mais texto'),
    Text('Ainda mais'),
  ],
)
```

**SOLUÇÃO 1 - Expanded:**
```dart
Row(
  children: [
    Expanded(
      child: Text(
        'Texto muito longo que não cabe',
        overflow: TextOverflow.ellipsis,
      ),
    ),
    Text('Mais texto'),
  ],
)
```

**SOLUÇÃO 2 - Wrap:**
```dart
Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    Text('Texto'),
    Text('Mais texto'),
    Text('Ainda mais'),
  ],
)
```

**SOLUÇÃO 3 - SingleChildScrollView horizontal:**
```dart
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(
    children: [
      Text('Texto'),
      Text('Mais texto'),
    ],
  ),
)
```

### 4. Padding Responsivo

**ANTES:**
```dart
Padding(
  padding: EdgeInsets.all(20), // Fixo
  child: MeuConteudo(),
)
```

**DEPOIS:**
```dart
Padding(
  padding: ResponsiveHelper.getPagePadding(context),
  child: MeuConteudo(),
)
```

### 5. Grid Responsivo

**ANTES:**
```dart
GridView.builder(
  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2, // Fixo
  ),
  itemBuilder: (context, index) => Card(...),
)
```

**DEPOIS:**
```dart
GridView.builder(
  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: ResponsiveHelper.getGridColumns(context),
  ),
  itemBuilder: (context, index) => Card(...),
)
```

## 🚨 Problemas Comuns e Soluções

### Problema 1: Barra Amarela (Overflow)

**Causa**: Widget excede o espaço disponível

**Solução**:
1. Envolver com `Expanded` ou `Flexible`
2. Usar `overflow: TextOverflow.ellipsis` em textos
3. Adicionar `SingleChildScrollView` se necessário
4. Usar `LayoutBuilder` para dimensões dinâmicas

### Problema 2: Tela Muito Larga no Desktop

**Causa**: Widget usa `double.infinity` sem limite

**Solução**:
```dart
Container(
  constraints: BoxConstraints(
    maxWidth: ResponsiveHelper.getMaxContentWidth(context),
  ),
  child: MeuConteudo(),
)
```

### Problema 3: Modal no Mobile (deve ser página)

**Causa**: Usando `showDialog` ou `showModalBottomSheet`

**Solução**: Usar `ResponsiveHelper.showResponsiveDialog`

### Problema 4: Texto Muito Pequeno no Desktop

**Causa**: Tamanho de fonte fixo

**Solução**:
```dart
Text(
  'Meu texto',
  style: TextStyle(
    fontSize: ResponsiveHelper.getResponsiveFontSize(context, 16),
  ),
)
```

## 📝 Checklist de Responsividade

Ao criar/editar uma página, verificar:

- [ ] ✅ No mobile, abre como página full-screen (não modal)
- [ ] ✅ No desktop, tem largura máxima (≤ 1200px)
- [ ] ✅ Padding responsivo (menor no mobile, maior no desktop)
- [ ] ✅ Sem overflow (barra amarela)
- [ ] ✅ Textos não cortados
- [ ] ✅ Botões acessíveis (tamanho mínimo 44x44)
- [ ] ✅ Grid/Lista adapta ao tamanho da tela
- [ ] ✅ Imagens responsivas (fit, constraints)
- [ ] ✅ AppBar com botão de voltar no mobile

## 🎨 Padrões de Design

### Mobile (< 600px)
- Navegação: Bottom navigation bar
- Layout: Single column
- Padding: 16px
- Font size: Base
- Modals: Full-screen pages

### Tablet (600-1024px)
- Navegação: Side drawer
- Layout: Two columns
- Padding: 24px
- Font size: Base * 1.1
- Modals: Bottom sheets

### Desktop (>= 1024px)
- Navegação: Side menu
- Layout: Three columns
- Padding: 32px
- Font size: Base * 1.2
- Modals: Dialogs com max-width

## 🔍 Como Testar

1. **Emulador Android** (vários tamanhos):
   - Pixel 5 (393 x 851)
   - Pixel Tablet (1600 x 2560)

2. **Chrome DevTools**:
   - F12 → Toggle device toolbar
   - Testar: Mobile S, Mobile M, Mobile L, Tablet, Desktop

3. **Comandos Flutter**:
```bash
# Desktop
flutter run -d windows

# Web (testar responsividade no browser)
flutter run -d chrome

# Android
flutter run -d <device_id>
```

## 📚 Exemplos de Páginas Corrigidas

- ✅ `ResponsiveHelper` criado
- ✅ Exemplo de uso disponível no código
- 🔄 Páginas para corrigir:
  - [ ] `service_register_page.dart`
  - [ ] `appointment_details_page.dart`
  - [ ] `checkout_page.dart`
  - [ ] `employee_register_page.dart`

## 🚀 Próximos Passos

1. Aplicar `ResponsiveHelper` nas páginas existentes
2. Testar em todos os dispositivos
3. Corrigir overflows específicos reportados
4. Adicionar testes de responsividade

---

**Dica**: Sempre testar no menor dispositivo primeiro (iPhone SE / 375px) e depois expandir!
