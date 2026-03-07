import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

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
            'Ao se cadastrar, sua loja aparece no App MarkaAI para todos os usuários da sua região. Eles escolhem o serviço e o horário livre.'
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
            'O plano Starter é gratuito com anúncios. Temos planos profissionais para remover anúncios e liberar recursos avançados.'
      },
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: faqs.length,
      itemBuilder: (context, index) {
        final faq = faqs[index];
        return ExpansionTile(
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
        );
      },
    );
  }
}
