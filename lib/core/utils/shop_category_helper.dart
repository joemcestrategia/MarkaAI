import 'package:flutter/material.dart';

class ShopCategoryHelper {
  static Color getCatColor(String category) {
    switch (category.toLowerCase()) {
      case 'barbearia':
        return const Color(0xFFE3F2FD);
      case 'beleza':
      case 'estética':
      case 'estetica':
      case 'esttica':
        return const Color(0xFFFCE4EC);
      case 'saúde':
      case 'saude':
      case 'sade':
        return const Color(0xFFE8F5E9);
      case 'bem-estar':
        return const Color(0xFFFFF3E0);
      default:
        return const Color(0xFFF5F7FA);
    }
  }

  static IconData getCatIcon(String category) {
    switch (category.toLowerCase()) {
      case 'barbearia':
        return Icons.content_cut;
      case 'beleza':
      case 'estética':
      case 'estetica':
      case 'esttica':
        return Icons.face;
      case 'saúde':
      case 'saude':
      case 'sade':
        return Icons.medical_services;
      case 'bem-estar':
        return Icons.self_improvement;
      default:
        return Icons.store;
    }
  }
}
