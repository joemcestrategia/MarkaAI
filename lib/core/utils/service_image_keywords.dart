class ServiceImageKeywords {
  static String getEnglishKeyword(String nome) {
    final lowerNome = nome.toLowerCase();

    // Barbeiro / Corte
    if (lowerNome.contains('corte') ||
        lowerNome.contains('barba') ||
        lowerNome.contains('degradê') ||
        lowerNome.contains('degrade') ||
        lowerNome.contains('pelezinho') ||
        lowerNome.contains('nevou') ||
        lowerNome.contains('barbeiro') ||
        lowerNome.contains('barbearia')) {
      return 'barbershop haircut';
    }

    // Tranças / Cabelo Afro
    if (lowerNome.contains('trança') ||
        lowerNome.contains('tranca') ||
        lowerNome.contains('nagô') ||
        lowerNome.contains('nago') ||
        lowerNome.contains('braid') ||
        lowerNome.contains('afro')) {
      return 'braids hair';
    }

    // Unhas
    if (lowerNome.contains('unha') ||
        lowerNome.contains('gel') ||
        lowerNome.contains('manicure') ||
        lowerNome.contains('pedicure') ||
        lowerNome.contains('esmalte') ||
        lowerNome.contains('fibra')) {
      return 'manicure nails';
    }

    // Maquiagem
    if (lowerNome.contains('maquiagem') ||
        lowerNome.contains('makeup') ||
        lowerNome.contains('make up')) {
      return 'makeup artist';
    }

    // Sobrancelha / Cílios
    if (lowerNome.contains('sobrancelha') ||
        lowerNome.contains('cilio') ||
        lowerNome.contains('cílio') ||
        lowerNome.contains('henna') ||
        lowerNome.contains('lash')) {
      return 'eyebrows lashes';
    }

    // Depilação
    if (lowerNome.contains('depilação') ||
        lowerNome.contains('depilacao') ||
        lowerNome.contains('cera') ||
        lowerNome.contains('wax')) {
      return 'waxing body';
    }

    // Massagem / Spa
    if (lowerNome.contains('massagem') ||
        lowerNome.contains('massage') ||
        lowerNome.contains('relaxante') ||
        lowerNome.contains('terapia') ||
        lowerNome.contains('spa')) {
      return 'massage therapy spa';
    }

    // Cabelo Feminino (Geral)
    if (lowerNome.contains('mechas') ||
        lowerNome.contains('luzes') ||
        lowerNome.contains('escova') ||
        lowerNome.contains('progressiva') ||
        lowerNome.contains('tintura') ||
        lowerNome.contains('coloração') ||
        lowerNome.contains('cabelo') ||
        lowerNome.contains('hair')) {
      return 'hair salon';
    }

    // Fallback padrão
    return 'beauty salon';
  }
}
