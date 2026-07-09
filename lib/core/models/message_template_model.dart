class MessageTemplate {
  final String? id;
  final String shopId;
  final String title;
  final String? content;
  final bool isDefault;
  final String? headerText;
  final String? footerText;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MessageTemplate({
    this.id,
    required this.shopId,
    required this.title,
    this.content,
    this.isDefault = false,
    this.headerText,
    this.footerText,
    this.createdAt,
    this.updatedAt,
  });

  factory MessageTemplate.fromMap(Map<String, dynamic> map) {
    return MessageTemplate(
      id: map['id'],
      shopId: map['shop_id'],
      title: map['title'] ?? '',
      content: map['content'],
      isDefault: map['is_default'] ?? false,
      headerText: map['header_text'],
      footerText: map['footer_text'],
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'shop_id': shopId,
      'title': title,
      'content': content,
      'is_default': isDefault,
      'header_text': headerText,
      'footer_text': footerText,
    };
  }

  // Helper method to generate full message content based on variables
  String generateFullMessage({
    required String clientName,
    required String serviceName,
    required String dateStr,
    required String timeStr,
  }) {
    if (isDefault) {
      final header = headerText ?? 'Olá, [NOME_CLIENTE]! 😊\n\nPassando para confirmar seu agendamento:';
      final footer = footerText ?? 'Te esperamos! Qualquer dúvida é só falar. 🙏';
      
      final processedHeader = header.replaceAll('[NOME_CLIENTE]', clientName);
      final processedFooter = footer.replaceAll('[NOME_CLIENTE]', clientName);

      return '$processedHeader\n\n✂️ $serviceName\n📅 $dateStr às $timeStr\n\n$processedFooter';
    } else {
      String processedContent = content ?? '';
      processedContent = processedContent.replaceAll('[NOME_CLIENTE]', clientName);
      processedContent = processedContent.replaceAll('[SERVICO]', serviceName);
      processedContent = processedContent.replaceAll('[DATA_HORA]', '$dateStr às $timeStr');
      processedContent = processedContent.replaceAll('[DATA]', dateStr);
      processedContent = processedContent.replaceAll('[HORA]', timeStr);
      return processedContent;
    }
  }
}
