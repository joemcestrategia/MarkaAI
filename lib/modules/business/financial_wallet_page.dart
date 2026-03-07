import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import 'payment_settings_page.dart';

class FinancialWalletPage extends StatefulWidget {
  const FinancialWalletPage({super.key});

  @override
  State<FinancialWalletPage> createState() => _FinancialWalletPageState();
}

class _FinancialWalletPageState extends State<FinancialWalletPage> {
  bool _isLoading = true;
  bool _showValues = true;
  bool _showSettings = false;
  String? _errorMessage;

  double totalAmount = 0.0;
  double availableAmount = 0.0;
  double unavailableAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchWalletData();
  }

  Future<void> _fetchWalletData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      String? shopId = await SessionService.getShopId();
      if (shopId == null) throw Exception("Erro de Sessão");
      final doc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .get();
      final data = doc.data() as Map<String, dynamic>;
      final accessToken = data['mp_access_token'] ?? data['access_token'];
      if (accessToken == null) {
        setState(() {
          _errorMessage = "TOKEN_MISSING";
          _isLoading = false;
        });
        return;
      }
      final response = await http.get(
        Uri.parse(
            'https://api.mercadopago.com/users/me/mercadopago_account/balance'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode == 200) {
        final mpData = jsonDecode(response.body);
        setState(() {
          totalAmount = (mpData['total_amount'] ?? 0).toDouble();
          availableAmount = (mpData['available_amount'] ?? 0).toDouble();
          unavailableAmount = (mpData['unavailable_amount'] ?? 0).toDouble();
          _isLoading = false;
        });
      } else {
        throw Exception("Erro API");
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage == "TOKEN_MISSING") return _buildSetupRequiredScreen();
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primaryPurple));
    }

    return Material(
      color: const Color(0xFFF2F4F8),
      child: Row(
        children: [
          // --- COLUNA 2: DASHBOARD ESTÃTICO ---
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(20), // Padding levemente reduzido
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderInfo(),
                  const SizedBox(height: 16),
                  _buildTotalBalanceCard(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: _buildInfoCard("Disponível", availableAmount,
                              Colors.green, Icons.check_circle)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildInfoCard("A Liberar", unavailableAmount,
                              Colors.orange, Icons.watch_later)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text("Gerenciamento",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildActionTile(
                      icon: Icons.settings_outlined,
                      title: "Configurar Chaves",
                      subtitle: "API Mercado Pago",
                      onTap: () => setState(() => _showSettings = true)),
                  const SizedBox(height: 8),
                  _buildActionTile(
                      icon: Icons.help_outline,
                      title: "Suporte Financeiro",
                      subtitle: "Dúvidas sobre taxas",
                      onTap: _showSupportDialog),
                  const Spacer(), // Empurra a nota de segurança para o fim sem scroll
                  _buildSecurityNote(),
                ],
              ),
            ),
          ),

          // --- COLUNA 3: PAINEL ESTÃTICO ---
          VerticalDivider(width: 1, color: Colors.grey[300]),
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.white,
              child: _showSettings
                  ? PaymentSettingsPage(onClose: () {
                      setState(() => _showSettings = false);
                      _fetchWalletData();
                    })
                  : const Center(
                      child: Opacity(
                          opacity: 0.2,
                          child: Icon(Icons.account_balance_wallet_outlined,
                              size: 80))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderInfo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("Minha Carteira",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        IconButton(
            icon: Icon(_showValues ? Icons.visibility : Icons.visibility_off,
                size: 20, color: Colors.grey),
            onPressed: () => setState(() => _showValues = !_showValues)),
      ],
    );
  }

  Widget _buildTotalBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppColors.primaryPurple, Color(0xFF6A1B9A)]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: AppColors.primaryPurple.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Saldo Total MP",
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
              _showValues
                  ? NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                      .format(totalAmount)
                  : "R\$ â€¢â€¢â€¢â€¢â€¢â€¢",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
      String title, double value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 8),
        Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
        Text(
            _showValues
                ? NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                    .format(value)
                : "â€¢â€¢â€¢â€¢",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))
      ]),
    );
  }

  Widget _buildActionTile(
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey[100]!),
            borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon, color: AppColors.primaryPurple, size: 18),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                Text(subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 10))
              ])),
          const Icon(Icons.chevron_right, size: 14, color: Colors.grey)
        ]),
      ),
    );
  }

  void _showSupportDialog() {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text("Suporte"),
                content: const Text("suporte@markaai.com"),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("OK"))
                ]));
  }

  Widget _buildSecurityNote() {
    return Row(children: const [
      Icon(Icons.security, size: 12, color: Colors.blue),
      SizedBox(width: 6),
      Text("Segurança TLS 1.3 Ativa",
          style: TextStyle(fontSize: 9, color: Colors.blue))
    ]);
  }

  Widget _buildSetupRequiredScreen() {
    return Material(
        color: const Color(0xFFF2F4F8),
        child: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text("Configuração Necessária",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ElevatedButton(
              onPressed: () => setState(() => _showSettings = true),
              child: const Text("Configurar Agora"))
        ])));
  }
}
