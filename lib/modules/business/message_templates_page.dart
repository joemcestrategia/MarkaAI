import 'package:flutter/material.dart';
import '../../core/models/message_template_model.dart';
import '../../core/services/message_template_service.dart';
import '../../core/theme/app_colors.dart';

class MessageTemplatesPage extends StatefulWidget {
  final String shopId;

  const MessageTemplatesPage({super.key, required this.shopId});

  @override
  State<MessageTemplatesPage> createState() => _MessageTemplatesPageState();
}

class _MessageTemplatesPageState extends State<MessageTemplatesPage> {
  final _service = MessageTemplateService();
  bool _isLoading = true;
  List<MessageTemplate> _templates = [];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    try {
      final templates = await _service.getTemplates(widget.shopId);
      setState(() {
        _templates = templates;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar templates: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showTemplateModal([MessageTemplate? template]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TemplateModal(
        shopId: widget.shopId,
        template: template,
        onSaved: () {
          _loadTemplates();
        },
      ),
    );
  }

  Future<void> _deleteTemplate(MessageTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Template'),
        content: Text('Deseja realmente excluir o template "${template.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _service.deleteTemplate(template.id!);
        _loadTemplates();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          "Mensagens Personalizadas",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTemplateModal(),
        backgroundColor: AppColors.primaryPurple,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Novo Template", style: TextStyle(color: Colors.white)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _templates.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _templates.length,
                  itemBuilder: (context, index) {
                    final template = _templates[index];
                    return _buildTemplateCard(template);
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.message_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Nenhum template encontrado.',
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(MessageTemplate template) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: InkWell(
        onTap: () => _showTemplateModal(template),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: template.isDefault ? Colors.blue[50] : AppColors.primaryPurple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  template.isDefault ? Icons.verified_rounded : Icons.mark_chat_read_rounded,
                  color: template.isDefault ? Colors.blue[700] : AppColors.primaryPurple,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            template.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (template.isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'PADRÃO',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.isDefault 
                          ? 'Mensagem padrão de confirmação do sistema.'
                          : (template.content ?? ''),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (!template.isDefault)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _deleteTemplate(template),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateModal extends StatefulWidget {
  final String shopId;
  final MessageTemplate? template;
  final VoidCallback onSaved;

  const _TemplateModal({
    required this.shopId,
    this.template,
    required this.onSaved,
  });

  @override
  State<_TemplateModal> createState() => _TemplateModalState();
}

class _TemplateModalState extends State<_TemplateModal> {
  final _formKey = GlobalKey<FormState>();
  final _service = MessageTemplateService();
  
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _headerController;
  late TextEditingController _footerController;
  
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.template?.title ?? '');
    _contentController = TextEditingController(text: widget.template?.content ?? '');
    _headerController = TextEditingController(text: widget.template?.headerText ?? '');
    _footerController = TextEditingController(text: widget.template?.footerText ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _headerController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  void _insertVariable(String variable) {
    if (widget.template?.isDefault == true) return; // Variáveis não inseríveis no padrão dessa forma

    final text = _contentController.text;
    final selection = _contentController.selection;
    
    if (selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, variable);
      _contentController.text = newText;
      _contentController.selection = TextSelection.collapsed(offset: selection.start + variable.length);
    } else {
      _contentController.text = text + variable;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final template = MessageTemplate(
        id: widget.template?.id,
        shopId: widget.shopId,
        title: widget.template?.isDefault == true ? widget.template!.title : _titleController.text,
        content: widget.template?.isDefault == true ? null : _contentController.text,
        headerText: widget.template?.isDefault == true ? _headerController.text : null,
        footerText: widget.template?.isDefault == true ? _footerController.text : null,
        isDefault: widget.template?.isDefault ?? false,
      );

      if (template.id == null) {
        await _service.createTemplate(template);
      } else {
        await _service.updateTemplate(template);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDefault = widget.template?.isDefault ?? false;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    
    return Container(
      margin: EdgeInsets.only(top: kToolbarHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, bottomInset + 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  widget.template == null ? 'Novo Template' : 'Editar Template',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                
                if (!isDefault)
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Título do Template (ex: Atraso)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.title),
                    ),
                    validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                  ),
                
                if (isDefault)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Este é o template padrão de confirmação. Você pode editar a introdução e a despedida.',
                            style: TextStyle(color: Colors.blue, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                const SizedBox(height: 16),

                if (!isDefault) ...[
                  // Botões de Variáveis
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildVariableChip('[NOME_CLIENTE]', 'Nome'),
                        const SizedBox(width: 8),
                        _buildVariableChip('[SERVICO]', 'Serviço'),
                        const SizedBox(width: 8),
                        _buildVariableChip('[DATA]', 'Data'),
                        const SizedBox(width: 8),
                        _buildVariableChip('[HORA]', 'Hora'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Campo de Mensagem Completa
                  TextFormField(
                    controller: _contentController,
                    decoration: InputDecoration(
                      labelText: 'Mensagem',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    maxLines: 6,
                    validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                  ),
                ] else ...[
                  // Campos Divididos para Mensagem Padrão
                  TextFormField(
                    controller: _headerController,
                    decoration: InputDecoration(
                      labelText: 'Introdução',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    maxLines: 3,
                    validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                  ),
                  
                  // Bloco Bloqueado Visual
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lock_outline, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 8),
                            Text('Dados do Agendamento (Fixo)', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '✂️ [Nome do Serviço]\n📅 [Data] às [Hora]',
                          style: TextStyle(color: Colors.black54, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  
                  TextFormField(
                    controller: _footerController,
                    decoration: InputDecoration(
                      labelText: 'Despedida',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    maxLines: 2,
                    validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                  ),
                ],

                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Salvar Template', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVariableChip(String variable, String label) {
    return ActionChip(
      label: Text('+$label', style: const TextStyle(fontSize: 12, color: AppColors.primaryPurple)),
      backgroundColor: AppColors.primaryPurple.withOpacity(0.1),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () => _insertVariable(variable),
    );
  }
}
