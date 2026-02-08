import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'login_page.dart';

class LoginChoicePage extends StatelessWidget {
  const LoginChoicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        iconTheme: const IconThemeData(color: Colors.black)
      ),
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo Centralizada para reforçar a marca
            Center(
              child: Image.asset('assets/images/logo_full.png', width: 180),
            ),
            const SizedBox(height: 60),
            const Text(
              "Como deseja prosseguir?",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            const Text(
              "Selecione uma opção para acessar o centro de comando MarkaAI.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 50),
            
            // Botão Entrar (Login)
            SizedBox(
              height: 55,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    // 🛡️ CORREÇÃO: Removido isNewUser que causava erro
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text(
                  "JÁ TENHO UMA CONTA", 
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Botão Criar Conta (Outlined)
            SizedBox(
              height: 55,
              child: OutlinedButton(
                onPressed: () {
                  // Aqui você pode apontar para sua RegisterPage futuramente
                  Navigator.push(
                    context,
                    // 🛡️ CORREÇÃO: Removido isNewUser que causava erro
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primaryPurple, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  "QUERO ME CADASTRAR", 
                  style: TextStyle(color: AppColors.primaryPurple, fontWeight: FontWeight.bold, fontSize: 14)
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}