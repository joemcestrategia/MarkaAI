import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/html_stub.dart' if (dart.library.html) 'dart:html' as html;

// ─────────────────────────────────────────────────────────────────────────────
// COMPORTAMENTO DE SCROLL (MOUSE DRAG NO WEB)
// ─────────────────────────────────────────────────────────────────────────────
class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTES VISUAIS
// ─────────────────────────────────────────────────────────────────────────────
const _kDark = Color(0xFF0A0A0F);
const _kPurple = Color(0xFF7C3AED);
const _kGold = Color(0xFFF5A623);
const _kBgLight = Color(0xFFF8F9FB);
const _kGreen = Color(0xFF22C55E);

// Unsplash photos (gratuitas, sem API)
const _heroImg =
    'https://images.unsplash.com/photo-1512428559087-560fa5ceab42?w=900&q=80&fit=crop';
const _closingImg =
    'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=900&q=80&fit=crop';
const _authorityImg =
    'https://images.unsplash.com/photo-1440330033336-99923b32bd75?w=900&q=80&fit=crop';
// Imagens de avatar removidas

// ─────────────────────────────────────────────────────────────────────────────
//  WIDGET PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────
class AffiliateLandingPage extends StatefulWidget {
  const AffiliateLandingPage({super.key});

  @override
  State<AffiliateLandingPage> createState() => _AffiliateLandingPageState();
}

class _AffiliateLandingPageState extends State<AffiliateLandingPage> {
  final _scrollController = ScrollController();
  bool _showTopBar = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      html.document.title = 'Seja um Parceiro MarkaAi | Programa de Afiliados B2B';
    }
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final show = _scrollController.offset > 80;
    if (show != _showTopBar) setState(() => _showTopBar = show);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _goToRegister() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      Navigator.pushNamed(context, '/afiliados/painel');
    } else {
      Navigator.pushNamed(context, '/login',
          arguments: {'redirect': '/afiliados/painel'});
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 600), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: _kBgLight,
      floatingActionButton: AnimatedOpacity(
        opacity: _showTopBar ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: FloatingActionButton(
          mini: true,
          backgroundColor: _kPurple,
          onPressed: _scrollToTop,
          child: const Icon(Icons.arrow_upward, color: Colors.white),
        ),
      ),
      body: Focus(
        autofocus: true,
        descendantsAreFocusable: true,
        child: ScrollConfiguration(
          behavior: MyCustomScrollBehavior(),
          child: CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Sticky top bar
              _buildStickyAppBar(),
    
              SliverList(
                delegate: SliverChildListDelegate([
                  _HeroSection(isWide: isWide, onCta: _goToRegister),
                  _ProblemSolutionSection(isWide: isWide),
                  _EarningsProfilesSection(isWide: isWide),
                  _SimulatorSection(isWide: isWide),
                  _ClosingSection(isWide: isWide, onCta: _goToRegister),
                  _FooterSection(),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStickyAppBar() {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      backgroundColor: _showTopBar ? Colors.white : Colors.transparent,
      shadowColor: Colors.black12,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 60,
      title: AnimatedOpacity(
        opacity: _showTopBar ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: Image.asset(
          'assets/images/logo_purple.png',
          height: 32,
          errorBuilder: (_, __, ___) =>
              const Text('MarkaAi', style: TextStyle(color: _kPurple, fontWeight: FontWeight.bold)),
        ),
      ),
      actions: [
        if (_showTopBar)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton(
              onPressed: _goToRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                elevation: 0,
              ),
              child: const Text('Quero começar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEÇÃO 1 – HERO
// ─────────────────────────────────────────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  final bool isWide;
  final VoidCallback onCta;
  const _HeroSection({required this.isWide, required this.onCta});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kDark,
      child: Column(
        children: [
          // ── Conteúdo principal
          Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 64 : 24,
              vertical: isWide ? 80 : 48,
            ),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 5, child: _heroText(context)),
                      const SizedBox(width: 60),
                      Expanded(flex: 4, child: _heroImage()),
                    ],
                  )
                : Column(children: [_heroText(context), const SizedBox(height: 40), _heroImage()]),
          ),
          // ── Métricas
          _HeroMetrics(isWide: isWide),
        ],
      ),
    );
  }

  Widget _heroText(BuildContext ctx) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Image.asset(
            'assets/images/logo_white.png',
            height: 36,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        _Badge('● Programa de Afiliados B2B · Pré-Lançamento',
            bg: _kPurple.withValues(alpha: 0.25), textColor: const Color(0xFFD4A0FF)),
        const SizedBox(height: 24),
        const Text(
          'Transforme indicações simples em uma máquina de renda real.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 42,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Conecte o comércio local à tecnologia do MarkaAi usando apenas o seu celular. Sem precisar vender nada, sem investir um centavo. Escolha como quer ser pago e comece hoje.',
          style: TextStyle(color: Colors.white70, fontSize: 18, height: 1.6),
        ),
        const SizedBox(height: 36),
        _CtaButton('Quero me tornar um Parceiro MarkaAi', onTap: () {
          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            Navigator.pushNamed(ctx, '/afiliados/painel');
          } else {
            Navigator.pushNamed(ctx, '/login',
                arguments: {'redirect': '/afiliados/painel'});
          }
        }),
        const SizedBox(height: 16),
        const Row(
          children: [
            Icon(Icons.rocket_launch_rounded, color: Colors.white38, size: 16),
            SizedBox(width: 6),
            Text(
              'Aproveite o mercado livre de concorrência na sua cidade',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  Widget _heroImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Image.network(
        _heroImg,
        height: 480,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: 480,
          color: _kPurple.withValues(alpha: 0.3),
          child: const Center(child: Icon(Icons.person, color: Colors.white38, size: 80)),
        ),
      ),
    );
  }
}

class _HeroMetrics extends StatelessWidget {
  final bool isWide;
  const _HeroMetrics({required this.isWide});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Recorrência', 'Ganho por lojista ativo'),
      ('Mercado Livre', 'Baixa concorrência atual'),
      ('R\$ 0', 'Investimento inicial'),
      ('100%', 'Digital, pelo celular'),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        color: Colors.white.withValues(alpha: 0.05),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 64 : 24,
        vertical: 28,
      ),
      child: isWide
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: items
                  .map((e) => _metricItem(e.$1, e.$2))
                  .expand((w) => [w, Container(height: 40, width: 1, color: Colors.white12)])
                  .toList()
                ..removeLast(),
            )
          : Wrap(
              spacing: 24,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: items.map((e) => _metricItem(e.$1, e.$2)).toList(),
            ),
    );
  }

  Widget _metricItem(String val, String label) {
    return Column(
      children: [
        Text(val, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEÇÃO 2 – PROBLEMA VS SOLUÇÃO
// ─────────────────────────────────────────────────────────────────────────────
class _ProblemSolutionSection extends StatelessWidget {
  final bool isWide;
  const _ProblemSolutionSection({required this.isWide});

  @override
  Widget build(BuildContext context) {
    return _Section(
      bg: Colors.white,
      child: Column(
        children: [
          _Badge('O produto vende sozinho', bg: _kPurple.withValues(alpha: 0.1), textColor: _kPurple),
          const SizedBox(height: 16),
          _SectionTitle('Você só faz a ponte.'),
          const SizedBox(height: 48),
          isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _FeatureCard('Planos Acessíveis', 'Com assinaturas a partir de R\$ 29,90, qualquer lojista, restaurante ou prestador de serviço consegue pagar. A barreira de entrada é quase zero.', Icons.monetization_on_outlined)),
                    const SizedBox(width: 24),
                    Expanded(child: _FeatureCard('Eles Precisam de Você', 'O comércio local precisa de tecnologia para sobreviver. Você não está "empurrando" um produto, está entregando a solução que eles já procuravam.', Icons.rocket_launch_rounded)),
                    const SizedBox(width: 24),
                    Expanded(child: _FeatureCard('Indicação em 1 Minuto', 'Viu uma loja nova no bairro? Mandou o seu link de afiliado, o lojista assinou, a comissão é sua. Simples assim.', Icons.phone_android_outlined)),
                  ],
                )
              : Column(children: [
                  _FeatureCard('Planos Acessíveis', 'Com assinaturas a partir de R\$ 29,90, qualquer lojista consegue pagar.', Icons.monetization_on_outlined),
                  const SizedBox(height: 24),
                  _FeatureCard('Eles Precisam de Você', 'O comércio local precisa de tecnologia para sobreviver.', Icons.rocket_launch_rounded),
                  const SizedBox(height: 24),
                  _FeatureCard('Indicação em 1 Minuto', 'Viu uma loja no bairro? Mande seu link de afiliado.', Icons.phone_android_outlined),
                ]),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final String title, desc;
  final IconData icon;
  const _FeatureCard(this.title, this.desc, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _kBgLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Icon(icon, color: _kPurple, size: 48),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
          const SizedBox(height: 12),
          Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.5)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEÇÃO 3 – COMO FUNCIONA
// ─────────────────────────────────────────────────────────────────────────────
class _EarningsProfilesSection extends StatelessWidget {
  final bool isWide;
  const _EarningsProfilesSection({required this.isWide});

  @override
  Widget build(BuildContext context) {
    return _Section(
      bg: _kBgLight,
      child: Column(
        children: [
          _Badge('Escolha o seu perfil de ganhos', bg: _kGold.withValues(alpha: 0.18), textColor: const Color(0xFFB45309)),
          const SizedBox(height: 16),
          _SectionTitle('Como você prefere receber suas comissões?'),
          const SizedBox(height: 12),
          const _SubText('No MarkaAi, você está no controle.'),
          const SizedBox(height: 48),
          isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _ProfileCard('O Acelerador', 'Dinheiro Rápido', 'Para quem quer dinheiro imediato na conta.', 'Você recebe um Valor Fixo logo na primeira mensalidade paga pelo estabelecimento.', 'Fechou a indicação? O dinheiro já entra no seu painel. Ideal para quem tem uma rede de contatos gigante e quer levantar caixa rápido girando no volume.', Icons.bolt_outlined, false)),
                    const SizedBox(width: 24),
                    Expanded(child: _ProfileCard('O Fazendeiro', 'Renda Passiva Mensal', 'Para quem quer construir um salário recorrente.', 'Você ganha 10% de comissão todos os meses, enquanto a loja for assinantes do MarkaAi.', 'Você trabalha bem uma única vez para indicar a loja, e continua recebendo o pagamento todos os meses, construindo uma verdadeira aposentadoria.', Icons.eco_outlined, true)),
                  ],
                )
              : Column(children: [
                    _ProfileCard('O Acelerador', 'Dinheiro Rápido', 'Para quem quer dinheiro imediato na conta.', 'Valor Fixo na primeira mensalidade.', 'Caixa rápido no volume.', Icons.bolt_outlined, false),
                    const SizedBox(height: 24),
                    _ProfileCard('O Fazendeiro', 'Renda Passiva Mensal', 'Para quem quer construir um salário recorrente.', '10% de comissão todos os meses.', 'Aposentadoria e renda passiva.', Icons.eco_outlined, true),
                ]),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String title, subtitle, perfil, comoFunciona, potencial;
  final IconData icon;
  final bool recommended;

  const _ProfileCard(this.title, this.subtitle, this.perfil, this.comoFunciona, this.potencial, this.icon, this.recommended);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: recommended ? _kGold : Colors.black.withValues(alpha: 0.05), width: recommended ? 2 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recommended)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: _kGold, borderRadius: BorderRadius.circular(12)),
              child: const Text('⭐ Recomendado', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          Row(
            children: [
              Icon(icon, color: _kPurple, size: 36),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: _kPurple, fontSize: 13)),
                ],
              )
            ],
          ),
          const SizedBox(height: 24),
          _item('Perfil', perfil),
          const SizedBox(height: 16),
          _item('Como funciona', comoFunciona),
          const SizedBox(height: 16),
          _item('O potencial', potencial),
        ],
      ),
    );
  }

  Widget _item(String label, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF374151))),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.5)),
      ],
    );
  }
}

// Seção 4 - Removida

// ─────────────────────────────────────────────────────────────────────────────
// SEÇÃO 5 – PROJEÇÃO DE GANHOS
// ─────────────────────────────────────────────────────────────────────────────
class _SimulatorSection extends StatelessWidget {
  final bool isWide;
  const _SimulatorSection({required this.isWide});

  @override
  Widget build(BuildContext context) {
    return _Section(
      bg: Colors.white,
      child: Column(
        children: [
          _Badge('Simulador Visual', bg: _kPurple.withValues(alpha: 0.1), textColor: _kPurple),
          const SizedBox(height: 16),
          _SectionTitle('Veja o poder do efeito "Bola de Neve" na Renda Passiva (10%)'),
          const SizedBox(height: 12),
          const _SubText('A mágica acontece quando você foca no longo prazo.\nVeja o que acontece se você indicar apenas 1 loja por dia no Plano Premium (R\$ 99,90):'),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kPurple, Color(0xFF4C1D95)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: _kPurple.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: Column(
              children: [
                _simulationRow('Mês 1', '30 lojas', 'R\$ 300,00', 'pingando na sua conta todo mês.'),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: Colors.white24),
                ),
                _simulationRow('Mês 3', '90 lojas', 'R\$ 900,00', 'todo mês. (Você já paga suas contas básicas!)'),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: Colors.white24),
                ),
                _simulationRow('Mês 6', '180 lojas', 'R\$ 1.800,00', 'de salário passivo. Todo santo mês, sem precisar indicar mais ninguém!'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '* Simulação baseada na retenção de clientes no Plano Premium.',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _simulationRow(String mes, String lojas, String valor, String desc) {
    return isWide
        ? Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(mes, style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold)),
              Text(lojas, style: const TextStyle(color: _kGold, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(width: 40),
              Text(valor, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
              Expanded(child: Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(desc, style: const TextStyle(color: Colors.white60, fontSize: 14)),
              )),
            ],
          )
        : Column(
            children: [
              Text(mes, style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(lojas, style: const TextStyle(color: _kGold, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(valor, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ],
          );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEÇÃO 6 – AUTORIDADE
// ─────────────────────────────────────────────────────────────────────────────
class _AuthoritySection extends StatelessWidget {
  final bool isWide;
  final VoidCallback onCta;
  const _AuthoritySection({required this.isWide, required this.onCta});

  @override
  Widget build(BuildContext context) {
    final segments = ['🍕 Restaurantes', '💊 Farmácias', '🦷 Clínicas', '👗 Lojas', '💈 Barbearias', '🛒 Mercados', '🏋️ Academias', '🚗 Oficinas'];

    return _Section(
      bg: Colors.white,
      child: Column(
        children: [
          _Badge('Por que é fácil indicar', bg: _kPurple.withValues(alpha: 0.08), textColor: _kPurple),
          const SizedBox(height: 16),
          _SectionTitle('Os estabelecimentos querem dizer sim.'),
          const SizedBox(height: 12),
          const _SubText('Você não precisa convencer ninguém. O MarkaAi resolve um problema que os lojistas já sentem.'),
          const SizedBox(height: 48),
          isWide
              ? Row(children: [
                  Expanded(child: _AuthCard(Icons.ads_click_outlined, 'Resolve um problema urgente',
                      'Gestão manual, perda de vendas e falta de dados são dores reais. O lojista enxerga o valor em minutos.')),
                  const SizedBox(width: 20),
                  Expanded(child: _AuthCard(Icons.card_giftcard_outlined, 'Demo 100% gratuita',
                      'O estabelecimento experimenta antes de assinar qualquer coisa. O risco percebido cai a zero.')),
                  const SizedBox(width: 20),
                  Expanded(child: _AuthCard(Icons.verified_outlined, 'Credibilidade construída',
                      'MarkaAi tem cases em múltiplos segmentos. Você indica com confiança — material de apoio pronto.')),
                ])
              : Column(children: [
                  _AuthCard(Icons.ads_click_outlined, 'Resolve um problema urgente', 'O lojista enxerga o valor em minutos.'),
                  const SizedBox(height: 16),
                  _AuthCard(Icons.card_giftcard_outlined, 'Demo 100% gratuita', 'O risco percebido cai a zero.'),
                  const SizedBox(height: 16),
                  _AuthCard(Icons.verified_outlined, 'Credibilidade construída', 'Você indica com confiança.'),
                ]),
          const SizedBox(height: 40),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.network(_authorityImg, height: 280, width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
          const SizedBox(height: 36),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: segments.map((s) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _kPurple.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: _kPurple.withValues(alpha: 0.2)),
                  ),
                  child: Text(s, style: const TextStyle(fontSize: 14, color: _kPurple, fontWeight: FontWeight.w500)),
                )).toList(),
          ),
          const SizedBox(height: 48),
          _CtaButton('Quero indicar agora — sem pagar nada →', onTap: onCta),
        ],
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  final IconData icon;
  final String title, text;
  const _AuthCard(this.icon, this.title, this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _kBgLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: _kPurple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: _kPurple, size: 28),
          ),
          const SizedBox(height: 20),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.6)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEÇÃO 7 – FAQ
// ─────────────────────────────────────────────────────────────────────────────
class _FaqSection extends StatelessWidget {
  final bool isWide;
  const _FaqSection({required this.isWide});

  static const _faqs = [
    ('Preciso pagar para ser afiliado?',
        'Não. O cadastro como afiliado MarkaAi é completamente gratuito, sem mensalidade e sem custo de adesão. Você só começa a ganhar — sem investir nada.'),
    ('Como e quando recebo minha comissão?',
        'As comissões são creditadas automaticamente no seu painel assim que o estabelecimento ativar o plano. O pagamento é feito mensalmente com relatório completo de cada indicação.'),
    ('Preciso ter experiência com vendas?',
        'Não. Você não precisa vender — você indica. Nosso time comercial entra em contato com o estabelecimento e fecha o negócio. Você só conecta as partes.'),
    ('E se eu não conhecer nenhum comerciante?',
        'A maioria começa assim. Nossa área de membros tem guia completo de como prospectar localmente — desde abordagem no Google Maps até scripts prontos para WhatsApp.'),
    ('Isso é pirâmide ou esquema de indicações?',
        'Não. Você recebe comissão por indicar um produto real para clientes reais. É o mesmo modelo que corretores de seguros usam há décadas — só que 100% digital e gratuito.'),
    ('Tem suporte para afiliados?',
        'Sim. Você tem acesso a painel com métricas em tempo real, materiais de divulgação prontos e suporte via chat em horário comercial.'),
  ];

  @override
  Widget build(BuildContext context) {
    return _Section(
      bg: _kBgLight,
      child: Column(
        children: [
          _Badge('Perguntas frequentes', bg: Colors.grey.shade100, textColor: const Color(0xFF374151)),
          const SizedBox(height: 16),
          _SectionTitle('Tirei sua dúvida antes de você perguntar.'),
          const SizedBox(height: 44),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: _faqs
                  .map((q) => _FaqItem(q.$1, q.$2))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqItem extends StatefulWidget {
  final String q, a;
  const _FaqItem(this.q, this.a);

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> with SingleTickerProviderStateMixin {
  bool _open = false;
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _open ? _kPurple.withValues(alpha: 0.4) : Colors.grey.shade200),
        boxShadow: _open
            ? [BoxShadow(color: _kPurple.withValues(alpha: 0.08), blurRadius: 12)]
            : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            InkWell(
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(widget.q,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _open ? _kPurple : const Color(0xFF111827)))),
                    AnimatedRotation(
                      turns: _open ? 0.25 : 0,
                      duration: const Duration(milliseconds: 260),
                      child: Icon(Icons.arrow_forward_ios_rounded,
                          size: 14, color: _open ? _kPurple : Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            SizeTransition(
              sizeFactor: _anim,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Text(widget.a,
                    style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14, height: 1.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEÇÃO 8 – COMPARATIVO
// ─────────────────────────────────────────────────────────────────────────────
class _ComparisonSection extends StatelessWidget {
  final bool isWide;
  const _ComparisonSection({required this.isWide});

  @override
  Widget build(BuildContext context) {
    return _Section(
      bg: Colors.white,
      child: Column(
        children: [
          _Badge('Comparativo', bg: Colors.blue.shade50, textColor: Colors.blue.shade800),
          const SizedBox(height: 16),
          _SectionTitle('MarkaAi vs. outras formas de renda extra.'),
          const SizedBox(height: 44),
          _CompTable(isWide: isWide),
        ],
      ),
    );
  }
}

class _CompTable extends StatelessWidget {
  final bool isWide;
  const _CompTable({required this.isWide});

  @override
  Widget build(BuildContext context) {
    final criterios = [
      ('Investimento inicial', '✅ Zero', '✅ Baixo', '❌ Médio/alto', '✅ Baixo'),
      ('Precisa de audiência', '✅ Não', '❌ Sim', '❌ Sim', '⚠️ Portfólio'),
      ('Depende de estoque', '✅ Não', '✅ Não', '❌ Sim', '✅ Não'),
      ('Modelo B2B real', '✅ Sim', '❌ Não', '⚠️ Parcial', '⚠️ Depende'),
      ('Comissão recorrente', '✅ Sim', '❌ Geralmente não', '❌ Não', '❌ Não'),
      ('Suporte dedicado', '✅ Sim', '⚠️ Varia', '⚠️ Varia', '❌ Não'),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Table(
        border: TableBorder.all(color: Colors.grey.shade200),
        defaultColumnWidth: const FlexColumnWidth(1),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFF1F1F2E)),
            children: ['Critério', 'MarkaAi ★', 'Afil. Info', 'Dropship', 'Freelancer']
                .mapIndexed((i, h) => _headerCell(h, highlight: i == 1))
                .toList(),
          ),
          ...criterios.map((r) => TableRow(children: [
                _compCell(r.$1, false, isLabel: true),
                _compCell(r.$2, true),
                _compCell(r.$3, false),
                _compCell(r.$4, false),
                _compCell(r.$5, false),
              ])),
        ],
      ),
    );
  }

  Widget _headerCell(String t, {bool highlight = false}) => Container(
        color: highlight ? _kPurple : null,
        padding: const EdgeInsets.all(14),
        child: Text(t,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: highlight ? Colors.white : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      );

  Widget _compCell(String t, bool highlight, {bool isLabel = false}) => Container(
        color: highlight ? _kPurple.withValues(alpha: 0.06) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Text(t,
            textAlign: isLabel ? TextAlign.left : TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                color: isLabel ? const Color(0xFF374151) : (highlight ? _kPurple : const Color(0xFF6B7280)),
                fontWeight: highlight ? FontWeight.w600 : FontWeight.normal)),
      );
}

extension _MapIndexed<T> on Iterable<T> {
  Iterable<R> mapIndexed<R>(R Function(int, T) f) sync* {
    var i = 0;
    for (final e in this) {
      yield f(i++, e);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEÇÃO 9 – FECHAMENTO
// ─────────────────────────────────────────────────────────────────────────────
class _ClosingSection extends StatelessWidget {
  final bool isWide;
  final VoidCallback onCta;
  const _ClosingSection({required this.isWide, required this.onCta});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Imagem de fundo com overlay
        SizedBox(
          width: double.infinity,
          height: isWide ? 620 : 700,
          child: Image.network(_closingImg, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: _kDark)),
        ),
        Container(
          width: double.infinity,
          height: isWide ? 620 : 700,
          color: _kDark.withValues(alpha: 0.82),
        ),
        // Conteúdo sobreposto
        SizedBox(
          width: double.infinity,
          height: isWide ? 620 : 700,
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 28, vertical: 60),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Badge('Última chamada',
                      bg: _kGold.withValues(alpha: 0.25), textColor: _kGold),
                  const SizedBox(height: 24),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: const Text(
                      'O comércio da sua cidade está cheio de oportunidades agora.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          letterSpacing: -0.5),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: const Text(
                      'Vai deixar outra pessoa indicar no seu lugar?',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 17, height: 1.6),
                    ),
                  ),
                  const SizedBox(height: 40),
                  _CtaButton('Criar minha conta de afiliado grátis', onTap: onCta, large: true),
                  const SizedBox(height: 28),
                  // Selos
                  Wrap(
                    spacing: 20,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: const [
                      _Seal('Cadastro 100% gratuito'),
                      _Seal('Sem cartão de crédito'),
                      _Seal('Cancele quando quiser'),
                      _Seal('Suporte em português'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Seal extends StatelessWidget {
  final String text;
  const _Seal(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: _kGreen, size: 16),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FOOTER
// ─────────────────────────────────────────────────────────────────────────────
class _FooterSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kDark,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: const [
          Text('MarkaAi', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 18)),
          SizedBox(height: 8),
          Text('© 2026 MarkaAi. Todos os direitos reservados.',
              style: TextStyle(color: Colors.white30, fontSize: 12)),
          SizedBox(height: 4),
          Text('Termos de Uso · Privacidade · Programa de Afiliados',
              style: TextStyle(color: Colors.white30, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPONENTES REUTILIZÁVEIS
// ─────────────────────────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final Widget child;
  final Color bg;
  const _Section({required this.child, required this.bg});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;
    return Container(
      color: bg,
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 80 : 24,
        vertical: isWide ? 80 : 56,
      ),
      child: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100), child: child)),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color bg, textColor;
  const _Badge(this.text, {required this.bg, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(30)),
        child: Text(text, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFF111827), height: 1.2),
    );
  }
}

class _SubText extends StatelessWidget {
  final String text;
  const _SubText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Color(0xFF6B7280), fontSize: 16, height: 1.6),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: _kPurple, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

class _CtaButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool large;
  const _CtaButton(this.label, {required this.onTap, this.large = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: large ? 60 : 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kGold,
          foregroundColor: Colors.black,
          padding: EdgeInsets.symmetric(horizontal: large ? 40 : 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          elevation: 6,
          shadowColor: _kGold.withValues(alpha: 0.5),
        ),
        child: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: large ? 17 : 15),
        ),
      ),
    );
  }
}
