import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../support/support_tickets_page.dart';

class HelpGuidePage extends StatelessWidget {
  const HelpGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Guia MarkaAI',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.primaryPurple,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: AppColors.gold,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Primeiros Passos'),
              Tab(text: 'Funções'),
              Tab(text: 'Dúvidas (FAQ)'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _StepsTab(),
            _FeaturesTab(),
            _FaqTab(),
          ],
        ),
      ),
    );
  }
}

class _StepsTab extends StatelessWidget {
  const _StepsTab();

  @override
  Widget build(BuildContext context) {
    final steps = [
      {
        'title': '1. Configure seu Perfil',
        'desc':
            'Vá em Perfil e adicione o nome da sua loja, logo, capa e endereço. Isso ajuda seus clientes a te encontrarem.',
        'icon': Icons.store_outlined
      },
      {
        'title': '2. Cadastre seus Serviços',
        'desc':
            'No menu "Meus Serviços", adicione o que você oferece, o preço e o tempo médio de atendimento.',
        'icon': Icons.design_services_outlined
      },
      {
        'title': '3. Sua Agenda Online',
        'desc':
            'Uma vez configurada, sua agenda já está online. Você pode adicionar agendamentos manuais clicando no "+" na aba de Agenda.',
        'icon': Icons.calendar_today_outlined
      },
      {
        'title': '4. Convide sua Equipe',
        'desc':
            'Se você tem funcionários, pode cadastrá-los em "Equipe" para que cada um tenha sua própria agenda integrada.',
        'icon': Icons.people_outline
      },
      {
        'title': '5. Controle seu Financeiro',
        'desc':
            'Toda vez que concluir um atendimento, o valor será somado ao seu faturamento semanal na aba Financeiro.',
        'icon': Icons.account_balance_wallet_outlined
      },
      {
        'title': '6. Crie Cupons para Fidelizar',
        'desc':
            'Em "Gerenciar Cupons", crie descontos exclusivos. Use o slider para definir a porcentagem e compartilhe a arte do cupom direto no WhatsApp.',
        'icon': Icons.confirmation_number_outlined
      },
      {
        'title': '7. Entenda suas Tags de Clientes',
        'desc':
            'O sistema classifica automaticamente seus clientes como VIP, Novo ou Sumido baseado na frequência de visitas, ajudando você a focar em quem importa.',
        'icon': Icons.label_important_outline
      },
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: steps.length,
      itemBuilder: (context, index) {
        final step = steps[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor:
                      AppColors.primaryPurple.withValues(alpha: 0.1),
                  child: Icon(step['icon'] as IconData,
                      color: AppColors.primaryPurple),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step['title'] as String,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        step['desc'] as String,
                        style: TextStyle(color: Colors.grey[700], height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FeaturesTab extends StatelessWidget {
  const _FeaturesTab();

  @override
  Widget build(BuildContext context) {
    final features = [
      {
        'title': 'Dashboard',
        'desc':
            'Visão rápida do seu faturamento da semana e dos próximos agendamentos do dia.',
        'icon': Icons.dashboard
      },
      {
        'title': 'Agenda',
        'desc':
            'Visualização em lista para facilitar a gestão dos horários atuais e futuros.',
        'icon': Icons.event_note
      },
      {
        'title': 'Financeiro',
        'desc':
            'Relatórios detalhados por período para você ter controle total do seu lucro.',
        'icon': Icons.bar_chart
      },
      {
        'title': 'Clientes',
        'desc':
            'Histórico completo de cada cliente, incluindo serviços realizados e datas.',
        'icon': Icons.person_pin
      },
      {
        'title': 'Estoque',
        'desc':
            'Cadastre produtos usados ou vendidos e receba avisos quando o estoque estiver baixo.',
        'icon': Icons.inventory_2_outlined
      },
      {
        'title': 'Cupons',
        'desc':
            'Gestão de descontos e promoções com geração de artes para compartilhamento.',
        'icon': Icons.confirmation_number
      },
      {
        'title': 'Tags Inteligentes',
        'desc':
            'O sistema monitora o comportamento dos clientes e aplica tags automáticas (VIP/Sumido).',
        'icon': Icons.auto_awesome
      },
    ];

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: features.length,
      itemBuilder: (context, index) {
        final f = features[index];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(f['icon'] as IconData,
                  size: 40, color: AppColors.primaryPurple),
              const SizedBox(height: 12),
              Text(f['title'] as String,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              Text(
                f['desc'] as String,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FaqTab extends StatelessWidget {
  const _FaqTab();

  @override
  Widget build(BuildContext context) {
    final faqs = [
      {
        'q': 'Como os clientes agendam comigo?',
        'a':
            'O fluxo principal e RECOMENDADO é o agendamento pelo seu link público. Ao compartilhar seu link (no Instagram, WhatsApp), o cliente escolhe o serviço e o horário sozinho. Isso elimina trocas de mensagens e ativa lembretes automáticos.'
      },
      {
        'q': 'Para que serve o Agendamento Manual?',
        'a':
            'O agendamento manual no painel deve ser usado para duas situações: \n1. LANÇAMENTO DE ATENDIMENTOS PASSADOS: registrar serviços já feitos para manter seu histórico e financeiro organizados. \n2. EXCEÇÕES: bloqueio de horários ou atendimentos que não passaram pelo fluxo online. \n\nDICA: Evite fazer do agendamento manual sua rotina principal. Incentive o autoagendamento fixando seu link na bio do Instagram e no WhatsApp.'
      },
      {
        'q': 'Como aumentar meus agendamentos online?',
        'a':
            'Sugerimos ações práticas: \n- Fixe o link no WhatsApp (mensagem automática). \n- Adicione o link na bio do Instagram. \n- Envie o link para sua base de clientes atual. \n- Coloque um QR Code no seu estabelecimento. \n- Mencione o link ao terminar cada atendimento.'
      },
      {
        'q': 'O sistema impede conflitos de horário?',
        'a':
            'Sim! O Markaai detecta automaticamente se um profissional já tem um compromisso e impede que dois clientes agendem no mesmo minuto, respeitando a duração de cada serviço.'
      },
      {
        'q': 'Como editar ou cancelar um agendamento?',
        'a':
            'Na aba Agenda, localize o atendimento, clique nele e você poderá alterar o horário, o profissional ou mudar o status para "Cancelado". O cliente receberá uma notificação.'
      },
      {
        'q': 'Como recebo o pagamento?',
        'a':
            'Atualmente, o pagamento é feito diretamente para você no momento do serviço. O App serve para gerenciar o agendamento e o financeiro.'
      },
      {
        'q': 'Posso cancelar um agendamento?',
        'a':
            'Sim. Vá na agenda, clique no agendamento e mude o status para "Cancelado". O cliente será notificado.'
      },
      {
        'q': 'Como funciona o controle de estoque?',
        'a':
            'Em "Estoque", você cadastra os itens. Ao usar um produto, você pode dar baixa manualmente para manter o controle.'
      },
      {
        'q': 'O App é gratuito?',
        'a':
            'Temos um Plano Free para você começar e Planos Profissionais com recursos avançados para escalar seu negócio.'
      },
      {
        'q': 'Como visualizar minha Agenda?',
        'a':
            'Na aba Agenda, você pode alternar entre as visões do dia e da semana. Se tiver funcionários, pode filtrar para ver a agenda de cada profissional separadamente clicando no filtro de equipe no topo.'
      },
      {
        'q': 'Quando devo usar o Agendamento Manual?',
        'a':
            'O agendamento manual deve ser usado para: \n1. LANÇAMENTO DE PASSADOS: Registrar serviços já feitos para alimentar seu financeiro e histórico. Perfeito para quem está chegando agora no Markaai. \n2. EXCEÇÕES: Bloqueios de horários ou atendimentos imprevistos. \n\nLembre-se: O manual NÃO deve ser sua rotina principal. O ideal é o cliente agendar pelo link para que os lembretes automáticos funcionem e você tenha menos trabalho manual.'
      },
      {
        'q': 'Dicas para seus clientes usarem o Link:',
        'a':
            '- Fixe o link na bio do Instagram. \n- Adicione como mensagem automática no WhatsApp Business. \n- Envie o link em massa para sua lista atual de clientes. \n- Imprima um QR Code na recepção. \n- Cite o link ao final de cada atendimento: "Na próxima, aproveite e agende pelo nosso link, é super rápido!"'
      },
      {
        'q': 'Como funciona o histórico e desempenho?',
        'a':
            'Em "Meus Clientes" ou no "Financeiro", você acessa o histórico completo. Lá você vê quem são seus clientes VIPs, quanto cada serviço rendeu e o desempenho de cada profissional da sua equipe.'
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...faqs.map((faq) => ExpansionTile(
          title: Text(faq['q'] as String,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(faq['a'] as String,
                  style: TextStyle(color: Colors.grey[700])),
            ),
          ],
        )),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Icon(Icons.support_agent_rounded, size: 36, color: Colors.grey[400]),
              const SizedBox(height: 10),
              const Text(
                'Não encontrou o que procurava?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'Se o problema persistir, abra um chamado e nossa equipe vai te ajudar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
              const SizedBox(height: 14),
              Builder(
                builder: (ctx) => OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    ctx,
                    MaterialPageRoute(builder: (_) => const SupportTicketsPage()),
                  ),
                  icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                  label: const Text('Abrir Chamado de Suporte'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
