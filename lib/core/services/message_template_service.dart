import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_template_model.dart';

class MessageTemplateService {
  final SupabaseClient _client = Supabase.instance.client;

  // List all templates for a shop
  Future<List<MessageTemplate>> getTemplates(String shopId) async {
    final response = await _client
        .from('message_templates')
        .select()
        .eq('shop_id', shopId)
        .order('is_default', ascending: false) // Puts default first
        .order('title', ascending: true);
        
    var templates = (response as List).map((map) => MessageTemplate.fromMap(map)).toList();
    
    // Auto-create birthday template if it doesn't exist
    final hasBirthday = templates.any((t) => t.isDefault && t.title == 'Mensagem de Aniversário');
    if (!hasBirthday) {
      final birthdayTemplate = MessageTemplate(
        shopId: shopId,
        title: 'Mensagem de Aniversário',
        content: 'Olá, [NOME_CLIENTE]! 🎉 Feliz Aniversário! Que seu dia seja muito especial. Um abraço da nossa equipe!',
        isDefault: true,
      );
      final created = await createTemplate(birthdayTemplate);
      templates.insert(0, created);
    }

    return templates;
  }

  // Create a new template
  Future<MessageTemplate> createTemplate(MessageTemplate template) async {
    final response = await _client
        .from('message_templates')
        .insert(template.toMap())
        .select()
        .single();
        
    return MessageTemplate.fromMap(response);
  }

  // Update a template
  Future<MessageTemplate> updateTemplate(MessageTemplate template) async {
    if (template.id == null) {
      throw Exception('Template ID is required for update');
    }
    
    final response = await _client
        .from('message_templates')
        .update(template.toMap())
        .eq('id', template.id!)
        .select()
        .single();
        
    return MessageTemplate.fromMap(response);
  }

  // Delete a template
  Future<void> deleteTemplate(String templateId) async {
    // We also should prevent deletion of default templates via RLS or UI.
    // The UI handles this, but here is a safety check as well.
    final current = await _client
        .from('message_templates')
        .select('is_default')
        .eq('id', templateId)
        .single();
        
    if (current['is_default'] == true) {
      throw Exception('Não é possível excluir o template padrão de confirmação.');
    }

    await _client
        .from('message_templates')
        .delete()
        .eq('id', templateId);
  }
}
