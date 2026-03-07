import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/tutorial_service.dart';

class AppOnboardingPage extends StatefulWidget {
  final bool isBusiness;
  final VoidCallback onFinish;

  const AppOnboardingPage({
    super.key,
    required this.isBusiness,
    required this.onFinish,
  });

  @override
  State<AppOnboardingPage> createState() => _AppOnboardingPageState();
}

class _AppOnboardingPageState extends State<AppOnboardingPage> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  late List<Map<String, dynamic>> _pages;

  @override
  void initState() {
    super.initState();
    _pages = widget.isBusiness ? _businessPages : _clientPages;
  }

  // CONTEÚDO BUSINESS
  final List<Map<String, dynamic>> _businessPages = [
    {
      'title': 'Bem-vindo ao MarkaAI Business',
      'desc':
          'A ferramenta completa para gerenciar sua barbearia, salão ou estética com inteligência.',
      'icon': FontAwesomeIcons.store,
      'color': AppColors.primaryPurple,
    },
    {
      'title': 'Configuração de Perfil',
      'desc':
          'Personalize sua loja com fotos, logo e endereço para atrair mais clientes na sua região.',
      'icon': FontAwesomeIcons.addressCard,
      'color': Colors.teal,
    },
    {
      'title': 'Agenda Inteligente',
      'desc':
          'Organize seus horários, evite conflitos e receba agendamentos online 24h por dia.',
      'icon': FontAwesomeIcons.calendarCheck,
      'color': Colors.blue,
    },
    {
      'title': 'Gestão de Equipe',
      'desc':
          'Adicione seus funcionários e permita que eles gerenciem suas próprias agendas integradas.',
      'icon': FontAwesomeIcons.users,
      'color': Colors.purple,
    },
    {
      'title': 'Financeiro e Estoque',
      'desc':
          'Acompanhe seu faturamento em tempo real e controle seus produtos de forma simplificada.',
      'icon': FontAwesomeIcons.boxesStacked,
      'color': Colors.green,
    },
    {
      'title': 'Tudo Pronto!',
      'desc':
          'Para um guia detalhado de cada função, acesse nosso menu "Ajuda / Tutorial" no painel.',
      'icon': FontAwesomeIcons.circleCheck,
      'color': AppColors.gold,
    },
  ];

  // CONTEÚDO CLIENTE
  final List<Map<String, dynamic>> _clientPages = [
    {
      'title': 'Encontre os Melhores',
      'desc':
          'Busque pelos melhores profissionais e estabelecimentos de beleza da sua região.',
      'icon': FontAwesomeIcons.magnifyingGlass,
      'color': AppColors.primaryPurple,
    },
    {
      'title': 'Agende em Segundos',
      'desc':
          'Escolha o serviço, o profissional e o horário ideal. Sem ligações, sem demora.',
      'icon': FontAwesomeIcons.clock,
      'color': Colors.blue,
    },
    {
      'title': 'Histórico e Favoritos',
      'desc':
          'Acesse seus agendamentos anteriores e refaça serviços com um toque.',
      'icon': FontAwesomeIcons.heart,
      'color': Colors.red,
    },
    {
      'title': 'Tudo Pronto!',
      'desc':
          'Ficou com alguma dúvida? Acesse o guia completo no menu do seu perfil.',
      'icon': FontAwesomeIcons.circleCheck,
      'color': AppColors.gold,
    },
  ];

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _finish() async {
    await TutorialService.markAsSeen(isBusiness: widget.isBusiness);
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Botão Pular
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finish,
                child:
                    const Text("Pular", style: TextStyle(color: Colors.grey)),
              ),
            ),

            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(40),
                          decoration: BoxDecoration(
                            color:
                                (page['color'] as Color).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: FaIcon(
                            page['icon'],
                            size: 80,
                            color: page['color'],
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          page['title'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page['desc'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Controles Inferiores
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Indicador de Páginas
                  Row(
                    children: List.generate(
                      _pages.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(right: 8),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? AppColors.primaryPurple
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),

                  // Botão Próximo
                  ElevatedButton(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_currentPage == _pages.length - 1
                            ? "Começar"
                            : "Próximo"),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
