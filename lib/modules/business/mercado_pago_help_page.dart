import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';

class MercadoPagoHelpPage extends StatelessWidget {
  const MercadoPagoHelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Tutorial de Integração", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIntroCard(),
            const SizedBox(height: 25),
            const Text(
              "SIGA O PASSO A PASSO:",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
            ),
            const SizedBox(height: 15),
            
            _buildStepCard(
              number: "1",
              title: "Acesse o Painel de Desenvolvedor",
              content: "Abra o navegador e acesse o site oficial de desenvolvedores do Mercado Pago.",
              action: _buildLinkBox(context, "https://www.mercadopago.com.br/developers/panel"),
            ),

            _buildStepCard(
              number: "2",
              title: "Crie uma Aplicação",
              content: "1. Faça login na sua conta do Mercado Pago.\n2. Clique em 'Suas Integrações'.\n3. Clique em 'Criar Aplicação'.\n4. Dê um nome (Ex: MarkaAI) e selecione 'Pagamento Online'.",
            ),

            _buildStepCard(
              number: "3",
              title: "Ative as Credenciais de Produção",
              content: "No menu lateral, vá em 'Credenciais de Produção'.\n\n⚠️ IMPORTANTE: Não use as credenciais de 'Teste' (Sandbox), senão o dinheiro não cairá na sua conta real.",
            ),

            _buildStepCard(
              number: "4",
              title: "Copie e Cole",
              content: "Você verá dois códigos:\n\n🔑 Public Key (Chave Pública)\n🔒 Access Token (Começa com APP_USR...)\n\nCopie esses códigos e cole nas configurações do App.",
              isLast: true,
            ),

            const SizedBox(height: 30),
            
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Nunca compartilhe seu Access Token com estranhos. Ele dá acesso à sua conta.",
                      style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primaryPurple, Color(0xFF7B1FA2)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.primaryPurple.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: const Row(
        children: [
          Icon(Icons.bolt, color: AppColors.gold, size: 40),
          SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Conecte sua Conta", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 5),
                Text("Receba pagamentos via Pix e Cartão com baixa automática no sistema.", style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard({required String number, required String title, required String content, Widget? action, bool isLast = false}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(color: AppColors.primaryPurple, shape: BoxShape.circle),
                child: Center(child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: Colors.grey.withValues(alpha: 0.3), margin: const EdgeInsets.symmetric(vertical: 5))),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(content, style: const TextStyle(color: Colors.black87, height: 1.5, fontSize: 14)),
                  if (action != null) ...[
                    const SizedBox(height: 10),
                    action,
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkBox(BuildContext context, String url) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              url,
              style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Link copiado!"), duration: Duration(seconds: 1)),
              );
            },
            tooltip: "Copiar Link",
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          )
        ],
      ),
    );
  }
}