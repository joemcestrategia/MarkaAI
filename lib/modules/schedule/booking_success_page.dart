import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class BookingSuccessPage extends StatelessWidget {
  final String serviceName;
  final String date;
  final String time;
  final String professionalName;
  final bool isPaid; // Se foi pago online ou não

  const BookingSuccessPage({
    super.key,
    required this.serviceName,
    required this.date,
    required this.time,
    required this.professionalName,
    required this.isPaid,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Animação de Sucesso (Ícone Pulsante)
              TweenAnimationBuilder(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (context, double value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      padding: const EdgeInsets.all(25),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle, size: 80, color: Colors.green),
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
              const Text(
                "Agendamento Confirmado!",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                "Seu horário foi reservado com sucesso.\n${isPaid ? 'O pagamento já foi processado.' : 'Realize o pagamento no local.'}",
                style: const TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Cartão de Resumo (Ticket)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FD),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _buildRow(Icons.content_cut, serviceName),
                    const Divider(height: 25),
                    _buildRow(Icons.person, professionalName),
                    const Divider(height: 25),
                    _buildRow(Icons.calendar_today, "$date às $time"),
                  ],
                ),
              ),
              
              const Spacer(),
              
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () {
                    // Volta para a Home e limpa a pilha de navegação
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 5,
                  ),
                  child: const Text("VOLTAR PARA O INÍCIO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryPurple, size: 20),
        const SizedBox(width: 15),
        Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
      ],
    );
  }
}