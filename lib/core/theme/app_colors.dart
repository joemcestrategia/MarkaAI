import 'package:flutter/material.dart';

class AppColors {
  // Cores Principais (Identidade Visual)
  static const Color primaryPurple = Color(0xFF6A1B9A); // Roxo Profundo
  static const Color deepPurple = Color(0xFF2D264B); // Roxo bem escuro
  static const Color gold = Color(0xFFFFD700); // Dourado

  // Tema Claro
  static const Color background = Colors.white;
  static const Color surface = Color(0xFFF5F7FA);
  static const Color softGrey = surface; // Alias para compatibilidade
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color border = Color(0xFFE0E0E0);

  // Tema Escuro
  static const Color darkBackground = Color(0xFF0F1117);
  static const Color darkSurface = Color(0xFF1A1D27);
  static const Color darkTextPrimary = Colors.white;
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkBorder = Color(0xFF334155);

  // Cores de Status
  static const Color errorRed = Color(0xFFD32F2F); 
  static const Color successGreen = Color(0xFF388E3C); 
}
