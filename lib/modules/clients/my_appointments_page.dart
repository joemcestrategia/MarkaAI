import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/mercado_pago_service.dart';
import '../schedule/checkout_transparente_page.dart';
import 'dart:convert';
import 'dart:async';

class MyAppointmentsPage extends StatefulWidget {
  const MyAppointmentsPage({super.key});

  @override
  State<MyAppointmentsPage> createState() => _MyAppointmentsPageState();
}

class _MyAppointmentsPageState extends State<MyAppointmentsPage> with SingleTickerProviderStateMixin {
  final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  Timer? _timerPolling;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _timerPolling?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  bool _isUpcoming(DocumentSnapshot appointment) {
    final data = appointment.data() as Map<String, dynamic>;
    final status = data['status']?.toString().toLowerCase() ?? '';
    final appointmentDate = (data['data_agendamento'] as Timestamp).toDate();
    final now = DateTime.now();
    
    // Próximos: futuros e não cancelados/concluídos
    return appointmentDate.isAfter(now) && 
           !status.contains('cancelado') && 
           status != 'concluido';
  }

  List<DocumentSnapshot> _filterAppointments(List<DocumentSnapshot> appointments, bool upcoming) {
    return appointments.where((apt) => upcoming ? _isUpcoming(apt) : !_isUpcoming(apt)).toList();
  }

  Future<Map<String, dynamic>> _getShopData(String shopId) async {
    try {
      final shopDoc = await FirebaseFirestore.instance.collection('shops').doc(shopId).get();
      if (shopDoc.exists) {
        final data = shopDoc.data()!;
        return {
          'nome': data['nome'] ?? 'Estabelecimento',
          'logo': data['logoUrl'] ?? data['imageUrl'] ?? '',
        };
      }
    } catch (e) {
      debugPrint('Erro ao buscar dados da loja: $e');
    }
    return {'nome': 'Estabelecimento', 'logo': ''};
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'confirmado':
      case 'concluido':
        return Colors.green;
      case 'pendente':
      case 'agendado':
        return Colors.orange;
      case 'cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String? status) {
    switch (status?.toLowerCase()) {
      case 'confirmado':
        return 'Confirmado';
      case 'concluido':
        return 'Concluído';
      case 'pendente':
        return 'Pendente';
      case 'agendado':
        return 'Agendado';
      case 'cancelado':
        return 'Cancelado';
      default:
        return 'Desconhecido';
    }
  }

  Future<void> _showPaymentOptions(DocumentSnapshot appointment) async {
    final data = appointment.data() as Map<String, dynamic>;
    final valorTotal = (data['valor_total'] ?? data['valor'] ?? 0).toDouble();
    final valorPago = (data['valor_pago'] ?? 0).toDouble();
    final valorRestante = valorTotal - valorPago;

    if (valorRestante <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não há valor pendente para este agendamento.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.4,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Pagar Valor Restante",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primaryPurple),
                ),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppColors.primaryPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("VALOR A PAGAR", style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    currencyFormat.format(valorRestante),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryPurple),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text("Escolha a forma de pagamento:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _processPixPayment(appointment, valorRestante);
                    },
                    icon: const Icon(Icons.qr_code),
                    label: const Text("PIX"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _processCardPayment(appointment, valorRestante);
                    },
                    icon: const Icon(Icons.credit_card),
                    label: const Text("CARTÃO"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processPixPayment(DocumentSnapshot appointment, double amount) async {
    final data = appointment.data() as Map<String, dynamic>;
    final shopId = data['shopId'];
    
    try {
      // Buscar access token da loja
      final shopDoc = await FirebaseFirestore.instance.collection('shops').doc(shopId).get();
      final shopData = shopDoc.data();
      final accessToken = shopData?['mercadopago']?['access_token'];
      
      if (accessToken == null) {
        _showError('Erro ao processar pagamento: loja não configurada');
        return;
      }
      
      final user = FirebaseAuth.instance.currentUser!;
      final result = await MercadoPagoService.gerarPix(
        accessToken: accessToken,
        amount: amount,
        emailCliente: user.email ?? "cliente@app.com",
        description: "Pagamento restante - ${data['servico_nome'] ?? 'Serviço'}",
      );
      
      final qrCode64 = result['point_of_interaction']['transaction_data']['qr_code_base64'];
      final copyPaste = result['point_of_interaction']['transaction_data']['qr_code'];
      final paymentId = result['id'].toString();
      
      if (mounted) {
        _startPixMonitoring(appointment, paymentId, amount);
        _showPixModal(qrCode64, copyPaste, appointment, amount);
      }
    } catch (e) {
      _showError("Erro ao gerar PIX: $e");
    }
  }

  void _startPixMonitoring(DocumentSnapshot appointment, String paymentId, double amount) {
    final data = appointment.data() as Map<String, dynamic>;
    final shopId = data['shopId'];
    
    _timerPolling?.cancel();
    _timerPolling = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final shopDoc = await FirebaseFirestore.instance.collection('shops').doc(shopId).get();
        final accessToken = shopDoc.data()?['mercadopago']?['access_token'];
        
        final status = await MercadoPagoService.verificarStatusPix(
          accessToken: accessToken!,
          paymentId: paymentId,
        );
        
        if (status == 'approved') {
          timer.cancel();
          await _updateAppointmentPayment(appointment, amount, 'Pix', paymentId);
          if (mounted) {
            Navigator.pop(context); // Fecha o modal do PIX
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Pagamento aprovado!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {}
    });
  }

  void _showPixModal(String qr64, String copyPaste, DocumentSnapshot appointment, double amount) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(25),
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Pague via Pix", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primaryPurple)),
                IconButton(
                  onPressed: () {
                    _timerPolling?.cancel();
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text("Valor: ${currencyFormat.format(amount)}", style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            if (qr64.isNotEmpty)
              Expanded(child: Image.memory(base64Decode(qr64)))
            else
              const Expanded(child: Center(child: Text('Erro ao gerar QR'))),
            const SizedBox(height: 20),
            const Text("Pix Copia e Cola:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        copyPaste,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: AppColors.primaryPurple),
                    onPressed: () {
                      // Copiar para clipboard
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Código copiado!")),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processCardPayment(DocumentSnapshot appointment, double amount) async {
    final data = appointment.data() as Map<String, dynamic>;
    final shopId = data['shopId'];
    final serviceDoc = await FirebaseFirestore.instance
        .collection('services')
        .doc(data['servicoId'])
        .get();
    
    // Buscar shop e professional docs
    final shopDoc = await FirebaseFirestore.instance.collection('shops').doc(shopId).get();
    final professionalDoc = data['profissionalId'] != null 
        ? await FirebaseFirestore.instance.collection('professionals').doc(data['profissionalId']).get()
        : null;
    
    final appointmentDate = (data['data_agendamento'] as Timestamp).toDate();
    
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutTransparentePage(
          shopId: shopId,
          valor: amount,
          orderId: "ORD-REMAINING-${appointment.id}-${DateTime.now().millisecondsSinceEpoch}",
          serviceDoc: serviceDoc,
          professionalDoc: professionalDoc ?? shopDoc,
          date: appointmentDate,
          time: TimeOfDay.fromDateTime(appointmentDate),
          collectOnly: false,
        ),
      ),
    );
    
    if (result != null && result['success'] == true) {
      await _updateAppointmentPayment(
        appointment,
        amount,
        'Cartão de Crédito',
        result['paymentId'].toString(),
      );
    }
  }

  Future<void> _updateAppointmentPayment(
    DocumentSnapshot appointment,
    double paidAmount,
    String method,
    String paymentId,
  ) async {
    final data = appointment.data() as Map<String, dynamic>;
    final currentPaid = (data['valor_pago'] ?? 0).toDouble();
    final newPaid = currentPaid + paidAmount;
    final valorTotal = (data['valor_total'] ?? data['valor'] ?? 0).toDouble();
    
    await FirebaseFirestore.instance.collection('appointments').doc(appointment.id).update({
      'valor_pago': newPaid,
      'restante_a_pagar': valorTotal - newPaid,
      'metodo_pagamento': method,
      'payment_id': paymentId,
      'status': 'confirmado',
      'pago_em': FieldValue.serverTimestamp(),
    });
    
    if (mounted) {
      setState(() {});
    }
  }

  bool _shouldShowActions(DocumentSnapshot appointment) {
    final data = appointment.data() as Map<String, dynamic>;
    final status = data['status']?.toString().toLowerCase() ?? '';
    final appointmentDate = (data['data_agendamento'] as Timestamp).toDate();
    final now = DateTime.now();
    
    // Não mostrar ações se já passou, foi cancelado ou concluído
    return appointmentDate.isAfter(now) && 
           !status.contains('cancelado') && 
           status != 'concluido';
  }

  bool _canCancelAppointment(DocumentSnapshot appointment) {
    final data = appointment.data() as Map<String, dynamic>;
    final appointmentDate = (data['data_agendamento'] as Timestamp).toDate();
    final now = DateTime.now();
    
    // Verifica se o agendamento é futuro
    if (!appointmentDate.isAfter(now)) return false;
    
    // Não pode cancelar se já pagou algo
    final valorPago = (data['valor_pago'] ?? 0).toDouble();
    if (valorPago > 0) return false;
    
    return true;
  }

  Future<void> _cancelAppointment(DocumentSnapshot appointment) async {
    final data = appointment.data() as Map<String, dynamic>;
    final shopId = data['shopId'];
    
    // Buscar configuração do tempo de cancelamento da loja
    int tempoMinimo = 24; // Padrão 24 horas
    try {
      final shopDoc = await FirebaseFirestore.instance.collection('shops').doc(shopId).get();
      final config = shopDoc.data()?['config'] as Map<String, dynamic>?;
      tempoMinimo = config?['tempo_cancelamento_horas'] ?? 24;
    } catch (e) {
      debugPrint('Erro ao buscar config: $e');
    }
    
    final appointmentDate = (data['data_agendamento'] as Timestamp).toDate();
    final now = DateTime.now();
    final horasRestantes = appointmentDate.difference(now).inHours;
    
    if (horasRestantes < tempoMinimo) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Não é possível cancelar'),
          content: Text(
            'O cancelamento deve ser feito com no mínimo $tempoMinimo horas de antecedência.\n\n'
            'Faltam apenas $horasRestantes horas para o agendamento.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ENTENDI'),
            ),
          ],
        ),
      );
      return;
    }
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Agendamento'),
        content: const Text('Tem certeza que deseja cancelar este agendamento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('NÃO'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('SIM, CANCELAR'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    try {
      await FirebaseFirestore.instance.collection('appointments').doc(appointment.id).update({
        'status': 'cancelado',
        'cancelado_em': FieldValue.serverTimestamp(),
        'cancelado_por': 'cliente',
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Agendamento cancelado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Erro ao cancelar: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Meus Agendamentos'),
          backgroundColor: AppColors.primaryPurple,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Você precisa estar logado')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Agendamentos'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          tabs: const [
            Tab(text: 'Próximos'),
            Tab(text: 'Histórico'),
          ],
        ),
      ),
      backgroundColor: const Color(0xFFF5F7FA),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('appointments')
            .where('clientId', isEqualTo: user.uid)
            .orderBy('data_agendamento', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 80, color: Colors.grey),
                  SizedBox(height: 20),
                  Text('Nenhum agendamento encontrado', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final allAppointments = snapshot.data!.docs;
          final upcomingAppointments = _filterAppointments(allAppointments, true);
          final historyAppointments = _filterAppointments(allAppointments, false);

          return TabBarView(
            controller: _tabController,
            children: [
              _buildAppointmentsList(upcomingAppointments, true),
              _buildAppointmentsList(historyAppointments, false),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAppointmentsList(List<DocumentSnapshot> appointments, bool isUpcoming) {
    if (appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isUpcoming ? Icons.event_available : Icons.history,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 20),
            Text(
              isUpcoming 
                ? 'Nenhum agendamento futuro' 
                : 'Nenhum histórico ainda',
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: appointments.length,
      itemBuilder: (context, index) {
        final appointment = appointments[index];
        return _buildAppointmentCard(appointment, isUpcoming);
      },
    );
  }

  Widget _buildAppointmentCard(DocumentSnapshot appointment, bool isUpcoming) {
    final data = appointment.data() as Map<String, dynamic>;
    final shopId = data['shopId'];
    final valorTotal = (data['valor_total'] ?? data['valor'] ?? 0).toDouble();
    final valorPago = (data['valor_pago'] ?? 0).toDouble();
    final valorRestante = valorTotal - valorPago;
    final appointmentDate = (data['data_agendamento'] as Timestamp).toDate();

    return FutureBuilder<Map<String, dynamic>>(
      future: _getShopData(shopId),
      builder: (context, shopSnapshot) {
        final shopData = shopSnapshot.data ?? {'nome': 'Carregando...', 'logo': ''};
        final shopName = shopData['nome'] as String;
        final shopLogo = shopData['logo'] as String;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header com logo e nome do estabelecimento
                Row(
                  children: [
                    // Logo do estabelecimento
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: shopLogo.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: shopLogo,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  color: AppColors.primaryPurple.withValues(alpha: 0.1),
                                  child: const Icon(Icons.store, color: AppColors.primaryPurple),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: AppColors.primaryPurple.withValues(alpha: 0.1),
                                  child: const Icon(Icons.store, color: AppColors.primaryPurple),
                                ),
                              )
                            : Container(
                                color: AppColors.primaryPurple.withValues(alpha: 0.1),
                                child: const Icon(Icons.store, color: AppColors.primaryPurple),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Nome do estabelecimento e status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shopName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data['servico_nome'] ?? 'Serviço',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(data['status']).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _getStatusText(data['status']),
                        style: TextStyle(
                          color: _getStatusColor(data['status']),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Data e hora
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('dd/MM/yyyy').format(appointmentDate),
                      style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('HH:mm').format(appointmentDate),
                      style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const Divider(height: 24),
                // Valores
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Valor Total:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(currencyFormat.format(valorTotal), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Pago:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          currencyFormat.format(valorPago),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: valorPago > 0 ? Colors.green : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Restante:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          currencyFormat.format(valorRestante),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: valorRestante > 0 ? Colors.orange : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Botões de ação (somente para próximos)
                if (isUpcoming && _shouldShowActions(appointment)) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Botão Cancelar
                      if (valorPago == 0 && _canCancelAppointment(appointment))
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _cancelAppointment(appointment),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('CANCELAR'),
                          ),
                        ),
                      if (valorPago == 0 && _canCancelAppointment(appointment) && valorRestante > 0)
                        const SizedBox(width: 12),
                      // Botão Pagar
                      if (valorRestante > 0)
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _showPaymentOptions(appointment),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('PAGAR RESTANTE'),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
