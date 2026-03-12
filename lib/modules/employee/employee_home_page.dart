import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../clients/shop_profile_page.dart';
import '../clients/my_appointments_page.dart';
import '../backup/calendar_backup_page.dart';
import '../business/appointment_details_page.dart';

/// Página Home para Funcionários (Modo Dual: Cliente + Funcionário)
///
/// Funcionalidades:
/// - Ver agendamentos de trabalho (como funcionário)
/// - Agendar serviços em outras lojas (como cliente)
/// - Gerenciar backup do Google Calendar
/// - Configurar folgas e indisponibilidades
class EmployeeHomePage extends StatefulWidget {
  final String employeeId;

  const EmployeeHomePage({
    super.key,
    required this.employeeId,
  });

  @override
  State<EmployeeHomePage> createState() => _EmployeeHomePageState();
}

class _EmployeeHomePageState extends State<EmployeeHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _employeeName = '';
  String? _employeePhotoUrl;
  // removed unused _shopId field
  int _todayAppointmentsCount = 0;
  int _upcomingAppointmentsCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadEmployeeData();
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployeeData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _employeeName = data['nome'] ?? 'Profissional';
          _employeePhotoUrl = data['foto_url'];
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao carregar dados do funcionário: $e');
    }
  }

  Future<void> _loadStats() async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      // Agendamentos de hoje
      final todaySnapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('profissionalId', isEqualTo: widget.employeeId)
          .where('data_agendamento',
              isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('data_agendamento', isLessThan: Timestamp.fromDate(todayEnd))
          .where('status',
              whereIn: ['confirmado', 'aguardando_confirmacao']).get();

      // Agendamentos futuros
      final upcomingSnapshot = await FirebaseFirestore.instance
          .collection('appointments')
          .where('profissionalId', isEqualTo: widget.employeeId)
          .where('data_agendamento',
              isGreaterThan: Timestamp.fromDate(todayEnd))
          .where('status',
              whereIn: ['confirmado', 'aguardando_confirmacao']).get();

      if (mounted) {
        setState(() {
          _todayAppointmentsCount = todaySnapshot.size;
          _upcomingAppointmentsCount = upcomingSnapshot.size;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao carregar estatísticas: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Minha Área'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(
                text: 'Meus Trabalhos',
                icon: Icon(Icons.work_outline, size: 20)),
            Tab(text: 'Explorar', icon: Icon(Icons.search, size: 20)),
            Tab(text: 'Configurações', icon: Icon(Icons.settings, size: 20)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWorkTab(),
          _buildExploreTab(),
          _buildSettingsTab(),
        ],
      ),
    );
  }

  // ============ ABA 1: MEUS TRABALHOS ============
  Widget _buildWorkTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadStats();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header com foto
            _buildProfileHeader(),

            const SizedBox(height: 24),

            // Cards de estatísticas
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Hoje',
                    _todayAppointmentsCount.toString(),
                    Icons.today,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    'Próximos',
                    _upcomingAppointmentsCount.toString(),
                    Icons.calendar_month,
                    Colors.green,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Lista de agendamentos de hoje
            const Text(
              'Agendamentos de Hoje',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            _buildTodayAppointmentsList(),

            const SizedBox(height: 24),

            // Botão para ver todos os agendamentos
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  // Navega para lista completa de agendamentos
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => _EmployeeAppointmentsListPage(
                        employeeId: widget.employeeId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.list),
                label: const Text('VER TODOS OS AGENDAMENTOS'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryPurple,
                  side: const BorderSide(color: AppColors.primaryPurple),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundImage: _employeePhotoUrl != null
                ? CachedNetworkImageProvider(_employeePhotoUrl!)
                : null,
            backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.2),
            child: _employeePhotoUrl == null
                ? const Icon(Icons.person,
                    color: AppColors.primaryPurple, size: 30)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _employeeName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Profissional',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayAppointmentsList() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('profissionalId', isEqualTo: widget.employeeId)
          .where('data_agendamento',
              isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('data_agendamento', isLessThan: Timestamp.fromDate(todayEnd))
          .orderBy('data_agendamento')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final appointments = snapshot.data!.docs;

        if (appointments.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'Nenhum agendamento para hoje',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        return Column(
          children: appointments.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _buildAppointmentCard(doc.id, data);
          }).toList(),
        );
      },
    );
  }

  Widget _buildAppointmentCard(
      String appointmentId, Map<String, dynamic> data) {
    final dataAgendamento = (data['data_agendamento'] as Timestamp?)?.toDate();
    if (dataAgendamento == null) return const SizedBox();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primaryPurple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.event,
            color: AppColors.primaryPurple,
          ),
        ),
        title: FutureBuilder<DocumentSnapshot>(
          future: data['servicoId'] != null
              ? FirebaseFirestore.instance
                  .collection('services')
                  .doc(data['servicoId'])
                  .get()
              : null,
          builder: (context, serviceSnap) {
            final serviceName = serviceSnap.hasData && serviceSnap.data!.exists
                ? (serviceSnap.data!.data() as Map)['nome']
                : 'Serviço';
            return Text(
              serviceName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            );
          },
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(DateFormat('HH:mm').format(dataAgendamento)),
            FutureBuilder<DocumentSnapshot>(
              future: data['clientId'] != null
                  ? FirebaseFirestore.instance
                      .collection('clients')
                      .doc(data['clientId'])
                      .get()
                  : null,
              builder: (context, clientSnap) {
                final clientName = clientSnap.hasData && clientSnap.data!.exists
                    ? (clientSnap.data!.data() as Map)['nome']
                    : 'Cliente';
                return Text(
                  'Cliente: $clientName',
                  style: const TextStyle(fontSize: 12),
                );
              },
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getStatusColor(data['status']).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _getStatusText(data['status']),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _getStatusColor(data['status']),
            ),
          ),
        ),
        onTap: () async {
          final doc = await FirebaseFirestore.instance
              .collection('appointments')
              .doc(appointmentId)
              .get();

          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AppointmentDetailsPage(
                  appointmentDoc: doc,
                  startInEditMode: false,
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'confirmado':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _getStatusText(String? status) {
    switch (status) {
      case 'confirmado':
        return 'Confirmado';
      case 'cancelado':
        return 'Cancelado';
      case 'aguardando_confirmacao':
        return 'Aguardando';
      default:
        return 'Pendente';
    }
  }

  // ============ ABA 2: EXPLORAR (COMO CLIENTE) ============
  Widget _buildExploreTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Agende Serviços',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Você também pode agendar serviços em outras lojas!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 20),

          // Lista de lojas disponíveis
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('shops')
                .where('ativo', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final shops = snapshot.data!.docs;

              return Column(
                children: shops.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _buildShopCard(doc, data);
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 20),

          // Botão para ver meus agendamentos como cliente
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyAppointmentsPage(),
                  ),
                );
              },
              icon: const Icon(Icons.calendar_today),
              label: const Text('MEUS AGENDAMENTOS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopCard(DocumentSnapshot shop, Map<String, dynamic> data) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          radius: 30,
          backgroundImage: data['logoUrl'] != null
              ? CachedNetworkImageProvider(data['logoUrl'])
              : null,
          backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.2),
          child: data['logoUrl'] == null
              ? const Icon(Icons.store, color: AppColors.primaryPurple)
              : null,
        ),
        title: Text(
          data['nome'] ?? 'Loja',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              data['endereco'] ?? '',
              style: const TextStyle(fontSize: 12),
            ),
            if (data['categoria'] != null)
              Text(
                data['categoria'],
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.primaryPurple,
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShopProfilePage(
                shopDoc: shop,
                onBookService: (sDoc) {
                  // O fluxo de agendamento já está implementado na ShopProfilePage
                },
              ),
            ),
          );
        },
      ),
    );
  }

  // ============ ABA 3: CONFIGURAÇÕES ============
  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configurações',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),

          // Backup do Google Calendar
          _buildSettingCard(
            icon: Icons.cloud_upload,
            iconColor: Colors.green,
            title: 'Backup Google Calendar',
            subtitle: 'Sincronize seus agendamentos de trabalho',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CalendarBackupPage(
                    isOwner: false,
                    employeeId: widget.employeeId,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          // Folgas e Disponibilidade
          _buildSettingCard(
            icon: Icons.event_busy,
            iconColor: Colors.orange,
            title: 'Folgas e Disponibilidade',
            subtitle: 'Gerencie suas ausências e horários',
            onTap: () {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Entre em contato com seu gerente para alterar folgas'),
                  ),
                );
              }
            },
          ),

          const SizedBox(height: 12),

          // Perfil
          _buildSettingCard(
            icon: Icons.person_outline,
            iconColor: Colors.blue,
            title: 'Meu Perfil',
            subtitle: 'Dados pessoais e informações',
            onTap: () {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Entre em contato com seu gerente para atualizar seu perfil'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}

// ============================================================================
// PÁGINA DE LISTA COMPLETA DE AGENDAMENTOS DO FUNCIONÁRIO
// ============================================================================

class _EmployeeAppointmentsListPage extends StatelessWidget {
  final String employeeId;

  const _EmployeeAppointmentsListPage({
    required this.employeeId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Meus Agendamentos'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('appointments')
            .where('profissionalId', isEqualTo: employeeId)
            .orderBy('data_agendamento', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final appointments = snapshot.data!.docs;

          if (appointments.isEmpty) {
            return const Center(
              child: Text(
                'Nenhum agendamento encontrado',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: appointments.length,
            itemBuilder: (context, index) {
              final doc = appointments[index];
              final data = doc.data() as Map<String, dynamic>;
              final dataAgendamento =
                  (data['data_agendamento'] as Timestamp?)?.toDate();

              if (dataAgendamento == null) return const SizedBox();

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: FutureBuilder<DocumentSnapshot>(
                    future: data['servicoId'] != null
                        ? FirebaseFirestore.instance
                            .collection('services')
                            .doc(data['servicoId'])
                            .get()
                        : null,
                    builder: (context, serviceSnap) {
                      final serviceName =
                          serviceSnap.hasData && serviceSnap.data!.exists
                              ? (serviceSnap.data!.data() as Map)['nome']
                              : 'Serviço';
                      return Text(
                        serviceName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('dd/MM/yyyy - HH:mm')
                            .format(dataAgendamento),
                      ),
                      FutureBuilder<DocumentSnapshot>(
                        future: data['clientId'] != null
                            ? FirebaseFirestore.instance
                                .collection('clients')
                                .doc(data['clientId'])
                                .get()
                            : null,
                        builder: (context, clientSnap) {
                          final clientName =
                              clientSnap.hasData && clientSnap.data!.exists
                                  ? (clientSnap.data!.data() as Map)['nome']
                                  : 'Cliente';
                          return Text(
                            'Cliente: $clientName',
                            style: const TextStyle(fontSize: 12),
                          );
                        },
                      ),
                    ],
                  ),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(data['status'])
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _getStatusText(data['status']),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getStatusColor(data['status']),
                      ),
                    ),
                  ),
                  onTap: () async {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AppointmentDetailsPage(
                          appointmentDoc: doc,
                          startInEditMode: false,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'confirmado':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _getStatusText(String? status) {
    switch (status) {
      case 'confirmado':
        return 'Confirmado';
      case 'cancelado':
        return 'Cancelado';
      case 'aguardando_confirmacao':
        return 'Aguardando';
      default:
        return 'Pendente';
    }
  }
}
