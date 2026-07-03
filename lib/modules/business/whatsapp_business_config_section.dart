import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/repositories/whatsapp_config_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/upgrade_modal.dart';
import 'package:url_launcher/url_launcher.dart';

class WhatsappBusinessConfigSection extends StatefulWidget {
  final String shopId;

  const WhatsappBusinessConfigSection({super.key, required this.shopId});

  @override
  State<WhatsappBusinessConfigSection> createState() => _WhatsappBusinessConfigSectionState();
}

class _WhatsappBusinessConfigSectionState extends State<WhatsappBusinessConfigSection> {
  final WhatsappConfigRepository _repository = WhatsappConfigRepository();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;

  String _shopPlan = 'free';

  final TextEditingController _phoneNumberIdController = TextEditingController();
  final TextEditingController _businessAccountIdController = TextEditingController();
  final TextEditingController _accessTokenController = TextEditingController();
  final TextEditingController _webhookTokenController = TextEditingController();
  final TextEditingController _templateConfirmedController = TextEditingController();
  final TextEditingController _templateReminderController = TextEditingController();

  bool _isActive = false;
  bool _obscureToken = true;
  String? _configId;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final shopRes = await Supabase.instance.client.from('shops').select('plan_id').eq('id', widget.shopId).maybeSingle();
      if (shopRes != null) {
        _shopPlan = shopRes['plan_id']?.toString().toLowerCase() ?? 'free';
      }

      final config = await _repository.getConfig(widget.shopId);
      if (config != null) {
        _configId = config.id;
        _phoneNumberIdController.text = config.waPhoneNumberId;
        _businessAccountIdController.text = config.waBusinessAccountId ?? '';
        _accessTokenController.text = config.waAccessToken;
        _webhookTokenController.text = config.waWebhookVerifyToken;
        _templateConfirmedController.text = config.waTemplateConfirmedName ?? '';
        _templateReminderController.text = config.waTemplateReminderName ?? '';
        _isActive = config.isActive;
      } else {
        // Generate a random webhook token for new integrations
        _webhookTokenController.text = const Uuid().v4();
      }
    } catch (e) {
      _showSnack("Erro ao carregar configurações: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    if (_phoneNumberIdController.text.isEmpty ||
        _accessTokenController.text.isEmpty ||
        _webhookTokenController.text.isEmpty) {
      _showSnack("Preencha os campos obrigatórios (Phone Number ID, Access Token e Webhook Token).", isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final config = ShopWhatsappConfig(
        id: _configId ?? '', // Supabase upsert requires valid UUID or omit. If empty, rely on generated default UUID. Wait, upsert handles missing id if we don't pass it or pass an empty string? Best to omit if null. Wait, our `toMap` method doesn't include 'id', so it works!
        shopId: widget.shopId,
        waPhoneNumberId: _phoneNumberIdController.text,
        waBusinessAccountId: _businessAccountIdController.text.isNotEmpty ? _businessAccountIdController.text : null,
        waAccessToken: _accessTokenController.text,
        waWebhookVerifyToken: _webhookTokenController.text,
        waTemplateConfirmedName: _templateConfirmedController.text.isNotEmpty ? _templateConfirmedController.text : null,
        waTemplateReminderName: _templateReminderController.text.isNotEmpty ? _templateReminderController.text : null,
        isActive: _isActive,
      );

      await _repository.saveConfig(config);
      _showSnack("Configurações do WhatsApp salvas com sucesso!");
    } catch (e) {
      _showSnack("Erro ao salvar: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _testConnection() async {
    if (_phoneNumberIdController.text.isEmpty || _accessTokenController.text.isEmpty) {
      _showSnack("Phone Number ID e Acess Token são obrigatórios para testar.", isError: true);
      return;
    }

    setState(() => _isTesting = true);
    try {
      bool success = await _repository.testConnection(
        _phoneNumberIdController.text,
        _accessTokenController.text,
      );

      if (success) {
        _showSnack("Conexão validada com sucesso! ✨");
      } else {
        _showSnack("Falha ao conectar. Verifique seus tokens ou o status no Meta App.", isError: true);
      }
    } catch (e) {
      _showSnack("Erro ao testar a conexão.", isError: true);
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  Future<void> _openDocs() async {
    final url = Uri.parse('https://developers.facebook.com/docs/whatsapp');
    if (!await launchUrl(url)) {
      _showSnack("Não foi possível abrir o link das instruções.", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp Business', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF25D366),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: const Color(0xFFF2F4F8),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF25D366)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // INSTRUÇÕES CARD
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(FontAwesomeIcons.circleInfo, color: Colors.blue.shade600, size: 20),
                            const SizedBox(width: 8),
                            const Text("Credenciais Oficiais (WABA)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text("Você precisa de uma conta ativa no portal de Desenvolvedores do Meta e gerar um Token Permanente.", style: TextStyle(fontSize: 13, color: Colors.black87)),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: _openDocs,
                          child: const Text("Como obter suas credenciais? Clique aqui", style: TextStyle(fontSize: 13, color: Colors.blue, decoration: TextDecoration.underline, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // FORMULÁRIO DE CREDENCIAIS
                  const Text("1. Integração da API", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryPurple)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildTextField("Phone Number ID *", _phoneNumberIdController, "Ex: 10452367198..."),
                        const SizedBox(height: 16),
                        _buildTextField("WhatsApp Business Account ID (Opcional)", _businessAccountIdController, "WABA ID"),
                        const SizedBox(height: 16),
                        
                        // Access Token com obscure
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("System User Access Token *", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _accessTokenController,
                              maxLength: 500,
                              buildCounter: (_, {required int currentLength, required bool isFocused, required int? maxLength}) => null,
                              obscureText: _obscureToken,
                              style: const TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                hintText: "EAA...",
                                hintStyle: const TextStyle(color: Colors.black38),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureToken ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                                  onPressed: () => setState(() => _obscureToken = !_obscureToken),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.black12)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.black12)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primaryPurple, width: 2)),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        _buildTextField("Webhook Verify Token *", _webhookTokenController, "Token gerado para a configuração do callback"),
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text("Utilize este Verify Token lá no painel da Meta ao assinar o webhook.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // TEMPLATES
                  const Text("2. Seus Templates Aprovados", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryPurple)),
                  const SizedBox(height: 6),
                  const Text("Informe o nome exato do template aprovado na Meta (ex: agendamento_confirmado).", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildTextField("Template Confirmação", _templateConfirmedController, "Nome do template de confirmação"),
                        const SizedBox(height: 16),
                        _buildTextField("Template Lembrete", _templateReminderController, "Nome do template de lembrete"),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ATIVAÇÃO GERAL
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _isActive ? const Color(0xFF25D366) : Colors.grey.shade300, width: 2)
                    ),
                    child: SwitchListTile(
                      title: const Text("Ativar Integração WhatsApp", style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text("Habilita o envio automático de mensagens para seus clientes"),
                      value: _isActive,
                      activeColor: const Color(0xFF25D366),
                      onChanged: (v) {
                        if (_shopPlan == 'free' || _shopPlan == 'starter' || _shopPlan == 'plus') {
                          UpgradeModal.show(context, featureName: 'Integração WhatsApp', requiredPlan: 'PRO');
                        } else {
                          setState(() => _isActive = v);
                        }
                      },
                    ),
                  ),

                  const SizedBox(height: 48),

                  // BOTÕES
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isTesting ? null : _testConnection,
                          icon: _isTesting 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                            : const Icon(Icons.sync_alt, size: 18),
                          label: Text(_isTesting ? "Testando..." : "Testar Conexão"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveConfig,
                          icon: _isSaving 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save, size: 18),
                          label: Text(_isSaving ? "Salvando..." : "Salvar Configuração"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 48),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint, {int maxLength = 500}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLength: maxLength,
          buildCounter: (_, {required int currentLength, required bool isFocused, required int? maxLength}) => null,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.black38),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.black12)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.black12)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primaryPurple, width: 2)),
          ),
        ),
      ],
    );
  }
}
