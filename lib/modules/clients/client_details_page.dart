import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart'; // Para abrir WhatsApp (Adicione ao pubspec se não tiver)
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

class ClientDetailsPage extends StatefulWidget {
  final Map<String, dynamic> clientData;
  final String clientId; // Pode ser o UID ou o Telefone/Nome (se manual)
  final VoidCallback onClose;

  const ClientDetailsPage({
    super.key,
    required this.clientData,
    required this.clientId,
    required this.onClose,
  });

  @override
  State<ClientDetailsPage> createState() => _ClientDetailsPageState();
}

class _ClientDetailsPageState extends State<ClientDetailsPage> {
  String? shopId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadShopId();
  }

  Future<void> _loadShopId() async {
    final id = await SessionService.getShopId();
    if (mounted) {
      setState(() {
        shopId = id;
        _isLoading = false;
      });
    }
  }

  Future<void> _launchWhatsApp() async {
    String phone = widget.clientData['telefone'] ?? "";
    // Limpa caracteres não numéricos
    phone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Telefone não cadastrado.")));
      return;
    }

    // Adiciona código do país se não tiver (Assumindo BR +55)
    if (phone.length <= 11) phone = "55$phone";

    final url = Uri.parse("https://wa.me/$phone");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Não foi possível abrir o WhatsApp.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    bool isManual = widget.clientData['origem'] == 'manual';
    Color themeColor = isManual ? Colors.orange : AppColors.primaryPurple;

    return Column(
      children: [
        // 1. CABEÇALHO DO DOSSIÊ
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
          ),
          child: Column(
            children: [
              // Botão Fechar (Topo Direita)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: widget.onClose,
                ),
              ),
              
              // Avatar Gigante
              CircleAvatar(
                radius: 40,
                backgroundColor: themeColor.withValues(alpha: 0.1),
                child: Text(
                  (widget.clientData['nome'] ?? "?").substring(0, 1).toUpperCase(),
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: themeColor),
                ),
              ),
              const SizedBox(height: 15),
              
              // Nome e Etiqueta
              Text(widget.clientData['nome'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              if (isManual)
                Container(
                  margin: const EdgeInsets.only(top: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(6)),
                  child: const Text("CLIENTE MANUAL", style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold)),
                ),

              const SizedBox(height: 15),

              // Ações Rápidas (WhatsApp)
              if (widget.clientData['telefone'] != null && widget.clientData['telefone'] != "Não informado")
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _launchWhatsApp,
                    icon: const Icon(Icons.chat, size: 18, color: Colors.green),
                    label: Text(widget.clientData['telefone'], style: const TextStyle(color: Colors.green)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.green)),
                  ),
                ),
            ],
          ),
        ),

        // 2. ESTATÍSTICAS (KPIs)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: _buildStatCard("Total Gasto", currency.format(widget.clientData['totalGasto']), Icons.monetization_on, Colors.green),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildStatCard("Visitas", "${widget.clientData['visitas']}", Icons.calendar_today, Colors.blue),
              ),
            ],
          ),
        ),

        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Align(alignment: Alignment.centerLeft, child: Text("Histórico de Agendamentos", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
        ),

        // 3. HISTÓRICO DE AGENDAMENTOS
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _getHistoryStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(child: Text("Sem histórico recente.", style: TextStyle(color: Colors.grey[400])));
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                itemCount: snapshot.data!.docs.length,
                separatorBuilder: (c, i) => const Divider(),
                itemBuilder: (context, index) {
                  final data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                  return _buildHistoryItem(data);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // 🚨 INTELIGÊNCIA DE BUSCA: Define como encontrar o histórico
  Stream<QuerySnapshot> _getHistoryStream() {
    final query = FirebaseFirestore.instance.collection('appointments').where('shopId', isEqualTo: shopId);
    
    // Se for Manual, busca pelo telefone (chave forte) ou nome (chave fraca)
    if (widget.clientData['origem'] == 'manual') {
      String tel = widget.clientData['telefone'];
      String nome = widget.clientData['nome'];

      if (tel != "Não informado" && tel.isNotEmpty) {
        // Tenta buscar por várias variações de campo de telefone para garantir
        return query.where('client_phone', isEqualTo: tel).orderBy('data_agendamento', descending: true).snapshots();
      } else {
         // Fallback: Busca por nome
         return query.where('client_name', isEqualTo: nome).orderBy('data_agendamento', descending: true).snapshots();
      }
    } 
    
    // Se for App, busca pelo ID do usuário (Garantido)
    else {
      return query.where('clientId', isEqualTo: widget.clientId).orderBy('data_agendamento', descending: true).snapshots();
    }
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> data) {
    DateTime date;
    try { date = (data['data_agendamento'] as Timestamp).toDate(); } catch(e) { date = DateTime.now(); }
    
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    double valor = double.tryParse(data['valor_total']?.toString() ?? "0") ?? 0.0;
    String servico = data['nome_servico'] ?? data['service_name'] ?? "Serviço";
    String status = data['status'] ?? 'agendado';

    Color statusColor = Colors.grey;
    if (status == 'concluido') statusColor = Colors.green;
    if (status == 'cancelado') statusColor = Colors.red;
    if (status == 'agendado') statusColor = Colors.blue;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(4)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(DateFormat("dd").format(date), style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(DateFormat("MMM").format(date), style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
      title: Text(servico, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      subtitle: Row(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 6, height: 6, 
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)
          ),
          const SizedBox(width: 4),
          Text(status.toUpperCase(), style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold)),
        ],
      ),
      trailing: Text(currency.format(valor), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}