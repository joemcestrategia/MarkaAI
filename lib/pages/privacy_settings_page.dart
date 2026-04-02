import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:io' if (dart.library.html) 'package:flutter_application_1/core/utils/io_stub.dart' as io;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme/app_colors.dart';
import '../core/docs/legal_documents.dart';
import '../pages/legal_viewer_page.dart';
import '../modules/login/login_page.dart';

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  bool _isLoading = false;

  Future<void> _exportData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final data = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      
      if (data == null) return;

      // Sanitizar dados
      data['exportado_em'] = DateTime.now().toIso8601String();

      String jsonStr = const JsonEncoder.withIndent('  ').convert(data);

      if (kIsWeb) {
        // Na web, mostramos o JSON no console por enquanto (download via web requer blobs)
        debugPrint('JSON de Exportação: $jsonStr');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dados exportados para o console do navegador.')),
          );
        }
        return;
      }

      final file = io.File(
          '${(await getTemporaryDirectory()).path}/meus_dados_markaai.json');
      await file.writeAsString(jsonStr);

      if (mounted) {
        await Share.shareXFiles([XFile(file.path)],
            subject: 'Meus Dados MarkaAI');
      }
    } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar dados: $e')),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Conta Permanentemente',
            style: TextStyle(color: Colors.red)),
        content: const Text(
          'Atenção: Esta ação é irreversível. Todos os seus dados pessoais, perfil, histórico de agendamentos e assinaturas serão apagados ou anonimizados permanentemente. Deseja prosseguir?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('EXCLUIR MINHA CONTA',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sessão expirada. Faça login novamente para excluir a conta.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // Forçar refresh do token para garantir JWT válido antes de invocar a função
      final sessionResult = await Supabase.instance.client.auth.refreshSession();
      if (sessionResult.session == null) {
        throw Exception('Sessão expirada. Faça login novamente para excluir a conta.');
      }
      final freshToken = sessionResult.session!.accessToken;

      // Timeout de 60s para evitar loading infinito caso a função trave
      final response = await Supabase.instance.client.functions
          .invoke(
            'deleteUserAccount',
            body: {'userId': currentUser.id},
            headers: {'Authorization': 'Bearer $freshToken'},
          )
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw Exception('A operação demorou muito. Tente novamente.'),
          );

      // O Flutter SDK NÃO lança exceção em status 4xx/5xx — verificamos manualmente
      final responseData = response.data;
      if (responseData is Map && responseData.containsKey('error')) {
        // Tratar erro 401 com mensagem amigável
        final errMsg = responseData['error'] as String? ?? '';
        if (errMsg.contains('Sessão') || errMsg.contains('inválida') || errMsg.contains('expirada')) {
          throw Exception('Sua sessão expirou. Faça login novamente e tente excluir a conta.');
        }
        throw Exception(errMsg);
      }

      await Supabase.instance.client.auth.signOut();

      if (mounted) {
        // Exibir mensagem de sucesso após deletar e sair da sessão
        await showDialog(
          context: context,
          barrierDismissible: false, // Força clicar em OK
          builder: (ctx) => AlertDialog(
            title: const Text('Conta Excluída', style: TextStyle(color: Colors.green)),
            content: const Text('Sua conta e todos os dados vinculados foram removidos com sucesso.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir conta: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Central de Privacidade"),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryPurple))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  "Gerencie seus dados e privacidade",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
                const SizedBox(height: 8),
                const Text(
                  "A MarkaAI respeita sua privacidade. Utilize as opções abaixo para ter controle total sobre suas informações de acordo com a LGPD.",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 24),

                // Documentos
                _buildSectionTitle("Documentos Legais"),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined,
                      color: AppColors.primaryPurple),
                  title: const Text("Política de Privacidade"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LegalViewerPage(
                        title: "Política de Privacidade",
                        markdownContent: LegalDocuments.privacyPolicy,
                      ),
                    ),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.description_outlined,
                      color: AppColors.primaryPurple),
                  title: const Text("Termos de Uso"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LegalViewerPage(
                        title: "Termos de Uso",
                        markdownContent: LegalDocuments.termsOfUse,
                      ),
                    ),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined,
                      color: AppColors.primaryPurple),
                  title: const Text("Política de Reembolso"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LegalViewerPage(
                        title: "Política de Reembolso",
                        markdownContent: LegalDocuments.refundPolicy,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // Dados
                _buildSectionTitle("Seus Dados (Art. 18 LGPD)"),
                ListTile(
                  leading:
                      const Icon(Icons.download_outlined, color: Colors.blue),
                  title: const Text("Exportar Meus Dados"),
                  subtitle: const Text(
                      "Baixe uma cópia dos dados que possuímos sobre você."),
                  onTap: _exportData,
                ),
                const SizedBox(height: 20),

                // Conta (Destrutivo)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Zona de Perigo",
                        style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "A exclusão de dados é irreversível. Perderá acesso imediato e qualquer assinatura ativa vinculada será encerrada.",
                        style: TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _deleteAccount,
                          icon: const Icon(Icons.delete_forever,
                              color: Colors.red),
                          label: const Text("Excluir Minha Conta",
                              style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Text(
        title,
        style: const TextStyle(
            fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black54),
      ),
    );
  }
}
