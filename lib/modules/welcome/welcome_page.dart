import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../login/login_choice_page.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 1. A Nova Logo (Substituindo o ícone antigo)
            Image.asset(
              'assets/images/logo_full.png',
              width: 280, // Tamanho generoso para destacar a marca
            ),
            
            const SizedBox(height: 10), // Espaço menor pois o logo já tem margem interna
            
            // 2. Slogan / Frase de Impacto
            // Como o logo já diz "MarkaAI", aqui colocamos o valor do app
            const Text(
              "Seu negócio em outro nível",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20, 
                fontWeight: FontWeight.w500, // Peso médio para elegância
                color: Colors.grey, // Cinza para não brigar com o logo
              ),
            ),
            
            const SizedBox(height: 60),
            
            // 3. Botão de Ação
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginChoicePage()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  elevation: 0, // Design Flat moderno
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)
                  ),
                ),
                child: const Text(
                  "VAMOS COMEÇAR",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0, // Espaçamento para facilitar leitura
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}