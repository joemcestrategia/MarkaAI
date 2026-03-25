import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';


class ClientAffiliatePage extends StatefulWidget {
  const ClientAffiliatePage({super.key});

  @override
  State<ClientAffiliatePage> createState() => _ClientAffiliatePageState();
}

class _ClientAffiliatePageState extends State<ClientAffiliatePage> {
  bool _isLoading = true;
  Map<String, dynamic>? _affiliateData;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAffiliateData();
  }

  Future<void> _loadAffiliateData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _affiliateData = null;
          _isLoading = false;
        });
        return;
      }

      final response = await Supabase.instance.client.functions.invoke(
        'affiliates',
        method: HttpMethod.get,
      );

      if (response.status == 200) {
        setState(() {
          _affiliateData = response.data;
          _isLoading = false;
        });
      } else if (response.status == 404) {
        // Person not yet an affiliate - response.data might be null or empty
        setState(() {
          _affiliateData = null;
          _isLoading = false;
        });
      } else {
        throw Exception(response.data?['error'] ?? 'Erro ao carregar dados');
      }
    } catch (e) {
      debugPrint('Error loading affiliate data: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _registerAffiliate() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'affiliates/register',
        method: HttpMethod.post,
        body: {'commission_type': 'recurring'},
      );

      if (response.status == 201) {
        await _loadAffiliateData();
      } else {
        throw Exception(response.data?['error'] ?? 'Erro ao cadastrar');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setupStripe() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'affiliates/stripe-connect',
        method: HttpMethod.post,
      );

      final url = response.data?['url'];
      if (url != null) {
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } else {
          throw 'Não foi possível abrir o link.';
        }
      } else {
        throw 'URL de onboarding não recebida.';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro no Stripe Connect: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _affiliateData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Afiliados')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Erro: $_error'),
              ElevatedButton(
                onPressed: _loadAffiliateData,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (_affiliateData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Painel de Afiliado')),
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.handshake_outlined, size: 80, color: AppColors.primaryPurple),
                const SizedBox(height: 24),
                const Text(
                  'Pronto para se tornar um parceiro?',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Ative sua conta de afiliado agora mesmo para gerar seu link exclusivo e começar a ganhar comissões recorrentes.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 50,
                  width: 300,
                  child: ElevatedButton(
                    onPressed: _registerAffiliate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    child: const Text('ATIVAR CONTA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _buildDashboardView();
  }


  Widget _buildDashboardView() {
    final aff = _affiliateData!;
    final status = aff['status'] ?? 'pending';
    final coupon = aff['coupon_code'] ?? '---';
    final referrals = aff['referrals']?[0]?['count'] ?? 0;
    final onboardingCompleted = aff['stripe_onboarding_completed'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text('Meu Painel de Afiliado'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAffiliateData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getStatusColor(status).withValues(alpha: 0.1),
                    child: Icon(_getStatusIcon(status), color: _getStatusColor(status)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Status da Conta', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          _getStatusText(status),
                          style: TextStyle(fontWeight: FontWeight.bold, color: _getStatusColor(status), fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Coupon Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primaryPurple, Color(0xFF9C27B0)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text('Seu Cupom de Indicação', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(
                    coupon,
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () {
                      Share.share('Use meu cupom $coupon e ganhe desconto na MarkaAI! Registre sua loja agora.');
                    },
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('COMPARTILHAR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primaryPurple,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Stats
            const Text('Resultados', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _statCard('Indicações', referrals.toString(), Icons.people_outline)),
                const SizedBox(width: 16),
                Expanded(
                  child: _statCard(
                    'Comissões', 
                    'R\$ ${(() {
                      final commissions = aff['commissions'] as List?;
                      if (commissions == null || commissions.isEmpty) return '0,00';
                      double total = 0;
                      for (var c in commissions) {
                        total += (c['amount'] ?? 0).toDouble();
                      }
                      return total.toStringAsFixed(2).replaceFirst('.', ',');
                    })()}', 
                    Icons.account_balance_wallet_outlined
                  )
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Stripe Section
            const Text('Pagamentos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.credit_card, color: Color(0xFF6772E5)),
                      const SizedBox(width: 12),
                      const Text('Configuração Stripe', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Icon(
                        onboardingCompleted ? Icons.check_circle : Icons.warning_amber_rounded,
                        color: onboardingCompleted ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    onboardingCompleted
                        ? 'Sua conta está conectada e pronta para receber pagamentos.'
                        : 'Você precisa concluir a configuração da sua conta Stripe para receber suas comissões.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _setupStripe,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: onboardingCompleted ? Colors.grey[300]! : const Color(0xFF6772E5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        onboardingCompleted ? 'GERENCIAR CONTA NO STRIPE' : 'CONCLUIR CONFIGURAÇÃO',
                        style: TextStyle(color: onboardingCompleted ? Colors.grey[600] : const Color(0xFF6772E5), fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryPurple, size: 24),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active': return Colors.green;
      case 'pending': return Colors.orange;
      case 'rejected': return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'active': return Icons.verified_user;
      case 'pending': return Icons.hourglass_empty;
      case 'rejected': return Icons.error_outline;
      default: return Icons.help_outline;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'active': return 'Ativa / Aprovada';
      case 'pending': return 'Aguardando Aprovação';
      case 'rejected': return 'Recusada';
      default: return 'Desconhecido';
    }
  }
}
