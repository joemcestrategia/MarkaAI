class ShopImageKeywords {
  static String getEnglishKeyword(String category) {
    final lower = category.toLowerCase().trim();

    if (lower.contains('trança') ||
        lower.contains('tranca') ||
        lower.contains('trancista') ||
        lower.contains('afro') ||
        lower.contains('braid')) {
      return 'braids hair salon afro';
    }
    if (lower.contains('barbearia') || lower.contains('barber')) {
      return 'barbershop interior';
    }
    if (lower.contains('manicure') || lower.contains('pedicure') ||
        lower.contains('unhas') || lower.contains('nail')) {
      return 'nail salon';
    }
    if (lower.contains('sobrancelha') ||
        lower.contains('cílio') ||
        lower.contains('cilio') ||
        lower.contains('lash')) {
      return 'eyebrows lashes studio';
    }
    if (lower.contains('maquiagem') || lower.contains('makeup')) {
      return 'makeup artist studio';
    }
    if (lower.contains('depilação') || lower.contains('depilacao') || lower.contains('wax')) {
      return 'waxing beauty salon';
    }
    if (lower.contains('massagem') ||
        lower.contains('massage') ||
        lower.contains('spa') ||
        lower.contains('relaxa')) {
      return 'massage therapy spa';
    }
    if (lower.contains('estética') ||
        lower.contains('estetica') ||
        lower.contains('aesthetic')) {
      return 'aesthetic clinic spa';
    }
    if (lower.contains('saúde') ||
        lower.contains('saude') ||
        lower.contains('clínica') ||
        lower.contains('clinica') ||
        lower.contains('médico') ||
        lower.contains('medico')) {
      return 'health wellness clinic';
    }
    if (lower.contains('bem-estar') ||
        lower.contains('bem estar') ||
        lower.contains('wellness') ||
        lower.contains('pilates') ||
        lower.contains('yoga')) {
      return 'wellness center';
    }
    if (lower.contains('beleza') ||
        lower.contains('salão') ||
        lower.contains('salao') ||
        lower.contains('cabeleireiro') ||
        lower.contains('hair')) {
      return 'beauty salon';
    }
    if (lower.contains('lavagem') ||
        lower.contains('car wash') ||
        lower.contains('carwash') ||
        lower.contains('automotivo')) {
      return 'car wash professional';
    }
    if (lower.contains('pet') || lower.contains('animal') || lower.contains('banho')) {
      return 'pet grooming salon';
    }
    if (lower.contains('tatuagem') ||
        lower.contains('tattoo') ||
        lower.contains('piercing')) {
      return 'tattoo studio';
    }

    return 'beauty salon';
  }
}
