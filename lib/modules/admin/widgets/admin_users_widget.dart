import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/admin_service.dart';

class AdminUsersWidget extends StatefulWidget {
  const AdminUsersWidget({super.key});

  @override
  State<AdminUsersWidget> createState() => _AdminUsersWidgetState();
}

class _AdminUsersWidgetState extends State<AdminUsersWidget> {
  String _searchQuery = '';
  String _activeFilter = 'all'; // all, unconfirmed, today, google_only, cliente, dono, funcionario

  Map<String, Map<String, dynamic>> _authSummary = {};
  bool _loadingAuthSummary = true;

  @override
  void initState() {
    super.initState();
    _loadAuthSummary();
  }

  Future<void> _loadAuthSummary() async {
    if (!mounted) return;
    setState(() => _loadingAuthSummary = true);
    try {
      final summary = await AdminService().getUsersAuthSummary();
      if (mounted) {
        setState(() {
          _authSummary = summary;
          _loadingAuthSummary = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAuthSummary = false);
    }
  }

  DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    final s = val.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  String _formatRelativeOrShortDate(dynamic val) {
    final dt = _parseDate(val);
    if (dt == null) return 'N/A';
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    if (isToday) {
      return 'Hoje às $hour:$min';
    }
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return '$day/$month/${dt.year} $hour:$min';
  }

  bool _isUserConfirmed(String userId, Map<String, dynamic> publicData) {
    final auth = _authSummary[userId];
    if (auth != null) {
      return auth['email_confirmed_at'] != null || auth['confirmed_at'] != null;
    }
    return publicData['verified'] == true;
  }

  List<String> _getUserProviders(String userId) {
    final auth = _authSummary[userId];
    if (auth == null) return [];
    final raw = auth['providers'];
    if (raw is List) {
      return raw.map((e) => e.toString().toLowerCase()).toList();
    }
    return [];
  }

  bool _isCreatedToday(String userId, Map<String, dynamic> publicData) {
    final auth = _authSummary[userId];
    final dt = _parseDate(
      auth?['created_at'] ?? auth?['auth_created_at'] ?? publicData['created_at'],
    );
    if (dt == null) return false;
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cardColor = cs.surface;
    final textColor = cs.onSurface;
    final borderColor = cs.onSurface.withValues(alpha: 0.1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;

        return Column(
          children: [
            // Barra de busca + botão de atualizar Auth (sem overflow em telas pequenas)
            Padding(
              padding: EdgeInsets.fromLTRB(isCompact ? 12 : 20, 16, isCompact ? 12 : 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      style: TextStyle(color: textColor, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Buscar por nome, e-mail, telefone, cidade ou CPF...',
                        hintStyle: TextStyle(
                          color: textColor.withValues(alpha: 0.4),
                          fontSize: 13.5,
                        ),
                        prefixIcon: Icon(Icons.search, color: cs.primary, size: 20),
                        filled: true,
                        fillColor: cardColor,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.primary, width: 1.5),
                        ),
                      ),
                      onChanged: (value) => setState(() => _searchQuery = value),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (isCompact)
                    IconButton.outlined(
                      tooltip: 'Sincronizar status de autenticação',
                      onPressed: _loadingAuthSummary ? null : _loadAuthSummary,
                      icon: _loadingAuthSummary
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.sync_rounded, color: cs.primary, size: 20),
                    )
                  else
                    Tooltip(
                      message: 'Sincronizar status de autenticação (Supabase Auth)',
                      child: OutlinedButton.icon(
                        onPressed: _loadingAuthSummary ? null : _loadAuthSummary,
                        icon: _loadingAuthSummary
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync_rounded, size: 18),
                        label: const Text('Atualizar Auth', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.primary,
                          side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Lista de usuários com filtros inteligentes
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: Supabase.instance.client
                    .from('users')
                    .stream(primaryKey: ['id'])
                    .order('created_at', ascending: false),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Erro: ${snapshot.error}'));
                  }

                  final allUsers = snapshot.data ?? [];

                  // Contadores para os filtros rápidos
                  int unconfirmedCount = 0;
                  int todayCount = 0;
                  int googleOnlyCount = 0;

                  for (final u in allUsers) {
                    final uid = (u['id'] ?? '').toString();
                    if (!_isUserConfirmed(uid, u)) unconfirmedCount++;
                    if (_isCreatedToday(uid, u)) todayCount++;
                    final provs = _getUserProviders(uid);
                    if (provs.contains('google') && !provs.contains('email')) {
                      googleOnlyCount++;
                    }
                  }

                  // Aplicar busca textual e filtros
                  final users = allUsers.where((data) {
                    final uid = (data['id'] ?? '').toString();
                    if (_searchQuery.isNotEmpty) {
                      final query = _searchQuery.toLowerCase();
                      final nome =
                          (data['name'] ?? data['nome'] ?? '').toString().toLowerCase();
                      final email = (data['email'] ?? '').toString().toLowerCase();
                      final phone = (data['phone'] ?? '').toString().toLowerCase();
                      final city = (data['city'] ?? '').toString().toLowerCase();
                      final docId = (data['documento'] ?? data['cpf'] ?? '')
                          .toString()
                          .toLowerCase();
                      final matchesText = nome.contains(query) ||
                          email.contains(query) ||
                          phone.contains(query) ||
                          city.contains(query) ||
                          docId.contains(query) ||
                          uid.toLowerCase().contains(query);
                      if (!matchesText) return false;
                    }

                    switch (_activeFilter) {
                      case 'unconfirmed':
                        return !_isUserConfirmed(uid, data);
                      case 'today':
                        return _isCreatedToday(uid, data);
                      case 'google_only':
                        final provs = _getUserProviders(uid);
                        return provs.contains('google') && !provs.contains('email');
                      case 'cliente':
                        return (data['role'] ?? 'cliente') == 'cliente';
                      case 'dono':
                        final r = (data['role'] ?? '').toString();
                        return r == 'dono' || r == 'business';
                      case 'funcionario':
                        return (data['role'] ?? '') == 'funcionario';
                      default:
                        return true;
                    }
                  }).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Chips de Filtro Rápido
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 20),
                        child: Row(
                          children: [
                            _buildFilterChip(
                              id: 'all',
                              label: 'Todos (${allUsers.length})',
                              icon: Icons.people_outline,
                              cs: cs,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              id: 'unconfirmed',
                              label: 'Não Confirmados ($unconfirmedCount)',
                              icon: Icons.mark_email_unread_outlined,
                              cs: cs,
                              highlightColor: Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              id: 'today',
                              label: 'Criados Hoje ($todayCount)',
                              icon: Icons.bolt_rounded,
                              cs: cs,
                              highlightColor: const Color(0xFF4F8EF7),
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              id: 'google_only',
                              label: 'Só Google / Sem Senha ($googleOnlyCount)',
                              icon: Icons.g_mobiledata_rounded,
                              cs: cs,
                              highlightColor: Colors.purpleAccent,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              id: 'cliente',
                              label: 'Clientes',
                              icon: Icons.person_outline,
                              cs: cs,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              id: 'dono',
                              label: 'Donos de Negócio',
                              icon: Icons.storefront_outlined,
                              cs: cs,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              id: 'funcionario',
                              label: 'Funcionários',
                              icon: Icons.badge_outlined,
                              cs: cs,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Listagem
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 20),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                            border: Border.all(color: borderColor),
                          ),
                          child: users.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      'Nenhum usuário encontrado para este filtro.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: textColor.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: users.length,
                                  separatorBuilder: (context, index) =>
                                      Divider(color: borderColor, height: 1),
                                  itemBuilder: (context, index) {
                                    final data = users[index];
                                    final id = (data['id'] ?? '').toString();
                                    final nome = (data['name'] ?? 'Sem nome').toString();
                                    final email = (data['email'] ?? '').toString();
                                    final phone = (data['phone'] ?? '').toString();
                                    final city = (data['city'] ?? '').toString();
                                    final tipo = (data['role'] ?? 'cliente').toString();

                                    final authInfo = _authSummary[id];
                                    final isConfirmed = _isUserConfirmed(id, data);
                                    final providers = _getUserProviders(id);
                                    final createdStr = _formatRelativeOrShortDate(
                                      authInfo?['created_at'] ??
                                          authInfo?['auth_created_at'] ??
                                          data['created_at'],
                                    );

                                    return InkWell(
                                      onTap: () => _openUserDetailsPage(data),
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: isCompact ? 12 : 20,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            CircleAvatar(
                                              radius: 20,
                                              backgroundColor: isConfirmed
                                                  ? cs.primary.withValues(alpha: 0.12)
                                                  : Colors.orange.withValues(alpha: 0.15),
                                              child: Text(
                                                nome.isNotEmpty
                                                    ? nome[0].toUpperCase()
                                                    : '?',
                                                style: TextStyle(
                                                  color: isConfirmed
                                                      ? cs.primary
                                                      : Colors.orange,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  // Wrap evita qualquer overflow horizontal de nome + tags
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 4,
                                                    crossAxisAlignment:
                                                        WrapCrossAlignment.center,
                                                    children: [
                                                      Text(
                                                        nome,
                                                        style: TextStyle(
                                                          color: textColor,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      _buildConfirmationBadge(isConfirmed),
                                                      if (providers.contains('google'))
                                                        _buildMiniTag(
                                                          'GOOGLE',
                                                          const Color(0xFF4285F4),
                                                        ),
                                                      if (providers.contains('email'))
                                                        _buildMiniTag(
                                                          'SENHA',
                                                          Colors.teal,
                                                        ),
                                                      _buildRoleBadge(tipo, cs, textColor),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    [
                                                      if (email.isNotEmpty) email,
                                                      if (phone.isNotEmpty) phone,
                                                      if (city.isNotEmpty) city,
                                                      'Criado: $createdStr',
                                                    ].join('  •  '),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: textColor.withValues(
                                                        alpha: 0.55,
                                                      ),
                                                      fontSize: 11.5,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              color: textColor.withValues(alpha: 0.35),
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRoleBadge(String tipo, ColorScheme cs, Color textColor) {
    final isBusiness = tipo == 'dono' || tipo == 'business';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isBusiness
            ? cs.tertiary.withValues(alpha: 0.12)
            : textColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        tipo.toUpperCase(),
        style: TextStyle(
          color: isBusiness ? cs.tertiary : textColor.withValues(alpha: 0.6),
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String id,
    required String label,
    required IconData icon,
    required ColorScheme cs,
    Color? highlightColor,
  }) {
    final selected = _activeFilter == id;
    final activeColor = highlightColor ?? cs.primary;
    return InkWell(
      onTap: () => setState(() => _activeFilter = id),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? activeColor.withValues(alpha: 0.18) : cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? activeColor : cs.onSurface.withValues(alpha: 0.12),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? activeColor : cs.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? activeColor : cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationBadge(bool isConfirmed) {
    final color = isConfirmed ? const Color(0xFF16A34A) : Colors.orange;
    final text = isConfirmed ? 'CONFIRMADO' : 'NÃO CONFIRMADO';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConfirmed ? Icons.verified_rounded : Icons.warning_amber_rounded,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ===========================================================================
  // NAVEGAÇÃO PARA PÁGINA PRÓPRIA DE DETALHES E DIAGNÓSTICO DO CLIENTE
  // ===========================================================================
  Future<void> _openUserDetailsPage(Map<String, dynamic> data) async {
    final id = (data['id'] ?? '').toString();
    final currentTheme = Theme.of(context);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: currentTheme,
          child: AdminUserDetailsPage(
            initialUserData: data,
            initialAuthSummary: _authSummary[id],
            onAuthUpdated: _loadAuthSummary,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PÁGINA DEDICADA DE FICHA, DIAGNÓSTICO E MOVIMENTOS DO CLIENTE
// =============================================================================
class AdminUserDetailsPage extends StatefulWidget {
  final Map<String, dynamic> initialUserData;
  final Map<String, dynamic>? initialAuthSummary;
  final VoidCallback onAuthUpdated;

  const AdminUserDetailsPage({
    super.key,
    required this.initialUserData,
    required this.initialAuthSummary,
    required this.onAuthUpdated,
  });

  @override
  State<AdminUserDetailsPage> createState() => _AdminUserDetailsPageState();
}

class _AdminUserDetailsPageState extends State<AdminUserDetailsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _loadingDetails = true;
  bool _actionInProgress = false;
  bool _movementsAscending = true; // true = do 1º ao último movimento
  Map<String, dynamic> _fullDiag = {};
  late Map<String, dynamic> _userData;

  // Controllers para edição cadastral
  late TextEditingController _nomeController;
  late TextEditingController _emailController;
  late TextEditingController _telefoneController;
  late TextEditingController _documentoController;
  late TextEditingController _cidadeController;
  String? _currentTipo;
  bool _isEditingProfile = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _userData = Map<String, dynamic>.from(widget.initialUserData);
    _nomeController = TextEditingController(text: _userData['name'] ?? '');
    _emailController = TextEditingController(text: _userData['email'] ?? '');
    _telefoneController = TextEditingController(text: _userData['phone'] ?? '');
    _documentoController = TextEditingController(
      text: _userData['documento'] ?? _userData['cpf'] ?? '',
    );
    _cidadeController = TextEditingController(text: _userData['city'] ?? '');
    _currentTipo = (_userData['role'] ?? 'cliente').toString();

    _fetchDiagnostics();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nomeController.dispose();
    _emailController.dispose();
    _telefoneController.dispose();
    _documentoController.dispose();
    _cidadeController.dispose();
    super.dispose();
  }

  Future<void> _fetchDiagnostics() async {
    if (!mounted) return;
    setState(() => _loadingDetails = true);
    try {
      final id = (_userData['id'] ?? '').toString();
      final res = await AdminService().getUserFullDiagnostics(id);
      if (mounted) {
        setState(() {
          _fullDiag = res;
          if (res['profile'] is Map) {
            _userData = Map<String, dynamic>.from(res['profile'] as Map);
          }
          _loadingDetails = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Map<String, dynamic> get _authData {
    if (_fullDiag['auth'] is Map) {
      return Map<String, dynamic>.from(_fullDiag['auth'] as Map);
    }
    return widget.initialAuthSummary ?? {};
  }

  List<Map<String, dynamic>> get _identities {
    final auth = _authData;
    if (auth['identities'] is List) {
      return (auth['identities'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    if (_fullDiag['identities'] is List) {
      return (_fullDiag['identities'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return [];
  }

  List<String> get _providers {
    final auth = _authData;
    final appMeta = auth['app_metadata'] is Map
        ? Map<String, dynamic>.from(auth['app_metadata'] as Map)
        : <String, dynamic>{};
    final fromMeta = appMeta['providers'] is List
        ? (appMeta['providers'] as List).map((e) => e.toString().toLowerCase()).toList()
        : <String>[];
    final fromSummary = auth['providers'] is List
        ? (auth['providers'] as List).map((e) => e.toString().toLowerCase()).toList()
        : <String>[];
    final fromIdentities = _identities
        .map((i) => (i['provider'] ?? '').toString().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();

    return {...fromMeta, ...fromSummary, ...fromIdentities}.toList();
  }

  bool get _isConfirmed {
    final auth = _authData;
    return auth['email_confirmed_at'] != null || auth['confirmed_at'] != null;
  }

  DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    final s = val.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  String _formatDateTime(dynamic val) {
    final dt = _parseDate(val);
    if (dt == null) return 'Não registrado';
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    return '$day/$month/$year às $hour:$min:$sec';
  }

  /// Constrói a lista unificada de movimentos do cliente com data e hora
  List<Map<String, dynamic>> _getMovementsList() {
    List<Map<String, dynamic>> list = [];
    if (_fullDiag['movements'] is List && (_fullDiag['movements'] as List).isNotEmpty) {
      list = (_fullDiag['movements'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } else {
      final auth = _authData;
      final createdAt = auth['created_at'] ?? _userData['created_at'];
      if (createdAt != null) {
        list.add({
          'timestamp': createdAt.toString(),
          'category': 'CONTA',
          'title': 'Cadastro Inicial na Plataforma',
          'details':
              'Conta criada como ${(_userData['role'] ?? 'cliente').toString().toUpperCase()}',
        });
      }
      if (auth['confirmation_sent_at'] != null) {
        list.add({
          'timestamp': auth['confirmation_sent_at'].toString(),
          'category': 'EMAIL',
          'title': 'Envio / Reenvio de Link de Confirmação',
          'details': 'Link de confirmação disparado para ${_userData['email'] ?? ''}',
        });
      }
      for (final idObj in _identities) {
        final prov = (idObj['provider'] ?? 'email').toString().toUpperCase();
        if (idObj['created_at'] != null) {
          list.add({
            'timestamp': idObj['created_at'].toString(),
            'category': 'LOGIN',
            'title': 'Vínculo de Acesso ($prov)',
            'details': 'Provedor $prov vinculado à conta',
          });
        }
        if (idObj['last_sign_in_at'] != null &&
            idObj['last_sign_in_at'] != idObj['created_at']) {
          list.add({
            'timestamp': idObj['last_sign_in_at'].toString(),
            'category': 'LOGIN',
            'title': 'Login via $prov',
            'details': 'Autenticação realizada via $prov',
          });
        }
      }
      final confirmedAt = auth['email_confirmed_at'] ?? auth['confirmed_at'];
      if (confirmedAt != null) {
        list.add({
          'timestamp': confirmedAt.toString(),
          'category': 'CONTA',
          'title': 'Conta / E-mail Confirmado',
          'details': 'Endereço de e-mail validado e liberado para acesso',
        });
      }
      if (auth['recovery_sent_at'] != null) {
        list.add({
          'timestamp': auth['recovery_sent_at'].toString(),
          'category': 'SENHA',
          'title': 'Solicitou "Esqueci minha senha"',
          'details': 'E-mail de redefinição de senha solicitado',
        });
      }
      if (auth['last_sign_in_at'] != null) {
        list.add({
          'timestamp': auth['last_sign_in_at'].toString(),
          'category': 'LOGIN',
          'title': 'Sessão Iniciada (Login)',
          'details': 'Acesso direto registrado no Supabase Auth',
        });
      }
    }

    list.sort((a, b) {
      final dtA = _parseDate(a['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dtB = _parseDate(b['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return _movementsAscending ? dtA.compareTo(dtB) : dtB.compareTo(dtA);
    });

    return list;
  }

  Color _getCategoryColor(String category) {
    switch (category.toUpperCase()) {
      case 'CONTA':
        return const Color(0xFF16A34A);
      case 'LOGIN':
        return const Color(0xFF4F8EF7);
      case 'SENHA':
        return Colors.purpleAccent;
      case 'EMAIL':
        return Colors.amber.shade700;
      case 'VITRINE':
        return Colors.cyan;
      case 'AGENDAMENTO':
        return Colors.teal;
      case 'PAGAMENTO':
        return Colors.green;
      case 'SUPORTE':
        return Colors.deepOrangeAccent;
      default:
        return Colors.blueGrey;
    }
  }

  /// Gera uma explicação inteligente e automática da situação da conta do cliente
  List<_DiagnosticInsight> _buildAutomatedInsights() {
    final insights = <_DiagnosticInsight>[];
    final auth = _authData;
    final isConfirmed = _isConfirmed;
    final provs = _providers;

    final createdDt = _parseDate(auth['created_at'] ?? _userData['created_at']);
    final confirmedDt = _parseDate(auth['email_confirmed_at'] ?? auth['confirmed_at']);
    final confSentDt = _parseDate(auth['confirmation_sent_at']);
    final recoveryDt = _parseDate(auth['recovery_sent_at']);
    final lastSignInDt = _parseDate(auth['last_sign_in_at']);

    // 1. Conta nova criada hoje?
    if (createdDt != null) {
      final now = DateTime.now();
      final isToday = createdDt.year == now.year &&
          createdDt.month == now.month &&
          createdDt.day == now.day;
      if (isToday) {
        insights.add(
          _DiagnosticInsight(
            icon: Icons.fiber_new_rounded,
            color: const Color(0xFF4F8EF7),
            title: 'Conta recém-criada (Hoje)',
            description:
                'Esta conta foi criada hoje (${_formatDateTime(createdDt)}).',
          ),
        );
      }
    }

    // 2. Status de Confirmação de E-mail
    if (!isConfirmed) {
      insights.add(
        _DiagnosticInsight(
          icon: Icons.warning_amber_rounded,
          color: Colors.orange,
          title: 'Conta NÃO confirmada (Bloqueio no Login com Senha)',
          description:
              'O cliente ainda não clicou no link de confirmação enviado por e-mail${confSentDt != null ? ' (último envio em ${_formatDateTime(confSentDt)})' : ''}. '
              'Quando ele tenta entrar com e-mail e senha, o app bloqueia dizendo que a conta não foi confirmada. '
              'Use o botão "Confirmar E-mail Agora" abaixo para liberar imediatamente.',
        ),
      );
    } else {
      final googleIdentity = _identities.where((i) => i['provider'] == 'google').toList();
      final hasEmailProvider = provs.contains('email');

      if (googleIdentity.isNotEmpty && !hasEmailProvider) {
        insights.add(
          _DiagnosticInsight(
            icon: Icons.info_outline_rounded,
            color: Colors.purpleAccent,
            title: 'Confirmada via Login com Google (Sem Senha Ativa)',
            description:
                'A conta está confirmada desde ${_formatDateTime(confirmedDt)}, porém apenas o provedor GOOGLE está vinculado. '
                'Se o cliente criou a conta com senha antes de confirmar o e-mail e depois clicou em "Entrar com Google", '
                'o Supabase confirmou a conta pelo Google e desativou a senha não confirmada. '
                'Ele pode entrar clicando em "Continuar com Google" OU você pode clicar em "Definir Nova Senha" abaixo para habilitar o login por e-mail e senha.',
          ),
        );
      } else {
        insights.add(
          _DiagnosticInsight(
            icon: Icons.verified_user_rounded,
            color: const Color(0xFF16A34A),
            title: 'Conta Confirmada e Liberada',
            description:
                'E-mail confirmado em ${_formatDateTime(confirmedDt)}. Métodos habilitados: ${provs.map((p) => p.toUpperCase()).join(', ')}.',
          ),
        );
      }
    }

    // 3. Pedido de recuperação de senha recente
    if (recoveryDt != null) {
      final afterLastLogin = lastSignInDt == null || recoveryDt.isAfter(lastSignInDt);
      insights.add(
        _DiagnosticInsight(
          icon: Icons.lock_reset_rounded,
          color: afterLastLogin ? Colors.amber : Colors.blueGrey,
          title: 'Solicitou "Esqueci minha senha"',
          description:
              'Último e-mail de recuperação enviado em ${_formatDateTime(recoveryDt)}. '
              '${afterLastLogin ? 'O cliente ainda não concluiu o login após pedir a recuperação. Se o e-mail não chegou para ele, defina uma senha manualmente abaixo.' : ''}',
        ),
      );
    }

    return insights;
  }

  Future<void> _handleConfirmEmailManually() async {
    final id = (_userData['id'] ?? '').toString();
    setState(() => _actionInProgress = true);
    try {
      await AdminService().confirmUserEmailManually(id);
      widget.onAuthUpdated();
      await _fetchDiagnostics();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('E-mail confirmado com sucesso! O cliente já pode fazer login.'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao confirmar e-mail: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _handleSetPasswordDialog() async {
    final id = (_userData['id'] ?? '').toString();
    final email = (_userData['email'] ?? '').toString();
    final phone = (_userData['phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    final defaultSuggestion =
        phone.length >= 6 ? phone.substring(phone.length - 6) : '123456';

    final passCtrl = TextEditingController(text: defaultSuggestion);
    final cs = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Definir Senha Manualmente'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Isso ativará o login por E-mail e Senha para $email e confirmará a conta automaticamente (sem precisar que o cliente clique em e-mail).',
                style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.75)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nova Senha (mínimo 6 caracteres)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sugestão preenchida com os últimos 6 dígitos do telefone (ou 123456).',
                style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (passCtrl.text.trim().length < 6) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('A senha deve ter pelo menos 6 caracteres.')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Definir Senha e Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final newPassword = passCtrl.text.trim();

    setState(() => _actionInProgress = true);
    try {
      await AdminService().setUserPasswordManually(id, newPassword);
      widget.onAuthUpdated();
      await _fetchDiagnostics();
      await Clipboard.setData(
        ClipboardData(
          text:
              'Olá! Liberamos o seu acesso no MarkaAI.\nE-mail: $email\nSenha: $newPassword',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Senha "$newPassword" definida e conta confirmada! Mensagem copiada para a área de transferência.',
            ),
            backgroundColor: const Color(0xFF16A34A),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao definir senha: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cardColor = cs.surface;
    final textColor = cs.onSurface;
    final borderColor = cs.onSurface.withValues(alpha: 0.1);

    final id = (_userData['id'] ?? '').toString();
    final nome = (_userData['name'] ?? 'Sem nome').toString();
    final email = (_userData['email'] ?? 'Sem e-mail').toString();
    final phone = (_userData['phone'] ?? '').toString();
    final city = (_userData['city'] ?? '').toString();
    final role = (_userData['role'] ?? 'cliente').toString().toUpperCase();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        foregroundColor: textColor,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Voltar para lista de usuários',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Ficha & Diagnóstico do Cliente',
          style: TextStyle(
            color: textColor,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Recarregar diagnóstico',
            icon: _loadingDetails
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.refresh_rounded, color: textColor.withValues(alpha: 0.7)),
            onPressed: _loadingDetails ? null : _fetchDiagnostics,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 680;
          final horizontalPad = isCompact ? 14.0 : 28.0;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cabeçalho da Página do Cliente
                  Container(
                    margin: EdgeInsets.fromLTRB(horizontalPad, 16, horizontalPad, 12),
                    padding: EdgeInsets.all(isCompact ? 16 : 20),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: isCompact ? 24 : 30,
                          backgroundColor: _isConfirmed
                              ? cs.primary.withValues(alpha: 0.14)
                              : Colors.orange.withValues(alpha: 0.18),
                          child: Text(
                            nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: _isConfirmed ? cs.primary : Colors.orange,
                              fontSize: isCompact ? 20 : 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    nome,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: isCompact ? 17 : 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  _buildHeaderStatusBadge(_isConfirmed),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      role,
                                      style: TextStyle(
                                        color: cs.primary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 14,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(text: email));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('E-mail copiado!')),
                                      );
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.email_outlined,
                                          size: 14,
                                          color: textColor.withValues(alpha: 0.55),
                                        ),
                                        const SizedBox(width: 5),
                                        Flexible(
                                          child: Text(
                                            email,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: textColor.withValues(alpha: 0.75),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.copy_rounded,
                                          size: 13,
                                          color: textColor.withValues(alpha: 0.4),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (phone.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.phone_outlined,
                                          size: 14,
                                          color: textColor.withValues(alpha: 0.55),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          phone,
                                          style: TextStyle(
                                            color: textColor.withValues(alpha: 0.7),
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (city.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.location_on_outlined,
                                          size: 14,
                                          color: textColor.withValues(alpha: 0.55),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          city,
                                          style: TextStyle(
                                            color: textColor.withValues(alpha: 0.7),
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Barra de Abas Responsiva (sem overflow em nenhum tamanho de tela)
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: horizontalPad),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: isCompact,
                      tabAlignment: isCompact ? TabAlignment.start : TabAlignment.fill,
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: textColor.withValues(alpha: 0.65),
                      labelStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                      tabs: const [
                        Tab(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.health_and_safety_outlined, size: 16),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Diagnóstico & Movimentos',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Tab(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_month_outlined, size: 16),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Atividade & Agendamentos',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Tab(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.manage_accounts_outlined, size: 16),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Cadastro & Edição',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Conteúdo das Abas em Página Cheia
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildAuthDiagnosticsTab(
                          cs,
                          cardColor,
                          textColor,
                          borderColor,
                          horizontalPad,
                        ),
                        _buildActivityTab(
                          cs,
                          cardColor,
                          textColor,
                          borderColor,
                          horizontalPad,
                        ),
                        _buildProfileEditTab(
                          cs,
                          cardColor,
                          textColor,
                          borderColor,
                          id,
                          horizontalPad,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderStatusBadge(bool isConfirmed) {
    final color = isConfirmed ? const Color(0xFF16A34A) : Colors.orange;
    final text = isConfirmed ? 'CONTA CONFIRMADA' : 'CONTA NÃO CONFIRMADA';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConfirmed ? Icons.verified_rounded : Icons.warning_amber_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ABA 1: DIAGNÓSTICO DE AUTENTICAÇÃO, AÇÕES E TABELA DE MOVIMENTOS
  // ===========================================================================
  Widget _buildAuthDiagnosticsTab(
    ColorScheme cs,
    Color cardColor,
    Color textColor,
    Color borderColor,
    double horizontalPad,
  ) {
    final auth = _authData;
    final insights = _buildAutomatedInsights();
    final recentEmails = _fullDiag['recent_emails'] is List
        ? (_fullDiag['recent_emails'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
        : <Map<String, dynamic>>[];

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontalPad, 4, horizontalPad, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Diagnóstico Inteligente
          ...insights.map(
            (ins) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ins.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ins.color.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(ins.icon, color: ins.color, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ins.title,
                          style: TextStyle(
                            color: ins.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ins.description,
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.85),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 6),

          // 2. Botões de Ação Rápida para o Suporte
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AÇÕES RÁPIDAS DE SUPORTE (SEM DEPENDER DE E-MAIL)',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: (_isConfirmed || _actionInProgress)
                          ? null
                          : _handleConfirmEmailManually,
                      icon: const Icon(Icons.mark_email_read_rounded, size: 17),
                      label: Text(
                        _isConfirmed ? 'E-mail Já Confirmado' : 'Confirmar E-mail Agora',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _actionInProgress ? null : _handleSetPasswordDialog,
                      icon: const Icon(Icons.password_rounded, size: 17),
                      label: const Text(
                        'Definir / Trocar Senha Manualmente',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // 3. TABELA CRONOLÓGICA DE MOVIMENTOS DO CLIENTE NA PLATAFORMA
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(
                'TABELA DE MOVIMENTOS DO CLIENTE (DATA E HORA EXATA)',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _movementsAscending = !_movementsAscending),
                icon: Icon(
                  _movementsAscending
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  size: 15,
                  color: cs.primary,
                ),
                label: Text(
                  _movementsAscending
                      ? 'Ordem: 1º ao Último (Passo a Passo)'
                      : 'Ordem: Mais Recentes Primeiro',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildMovementsTable(cs, cardColor, textColor, borderColor),

          const SizedBox(height: 22),

          // 4. Status dos Marcos de Autenticação (Supabase Auth)
          Text(
            'STATUS DOS MARCOS DE AUTENTICAÇÃO (AUTH.USERS)',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                _buildTimelineRow(
                  icon: Icons.person_add_alt_1_rounded,
                  color: const Color(0xFF4F8EF7),
                  label: '1. Criação da Conta (Cadastro inicial)',
                  value: _formatDateTime(auth['created_at'] ?? _userData['created_at']),
                  textColor: textColor,
                ),
                Divider(color: borderColor, height: 20),
                _buildTimelineRow(
                  icon: Icons.forward_to_inbox_rounded,
                  color: Colors.amber,
                  label: '2. Último E-mail de Confirmação Enviado',
                  value: _formatDateTime(auth['confirmation_sent_at']),
                  textColor: textColor,
                ),
                Divider(color: borderColor, height: 20),
                _buildTimelineRow(
                  icon: _isConfirmed
                      ? Icons.verified_rounded
                      : Icons.hourglass_empty_rounded,
                  color: _isConfirmed ? const Color(0xFF16A34A) : Colors.orange,
                  label: '3. Confirmação do E-mail (email_confirmed_at)',
                  value: _isConfirmed
                      ? _formatDateTime(
                          auth['email_confirmed_at'] ?? auth['confirmed_at'],
                        )
                      : 'PENDENTE (Não confirmado)',
                  textColor: textColor,
                ),
                Divider(color: borderColor, height: 20),
                _buildTimelineRow(
                  icon: Icons.lock_reset_rounded,
                  color: Colors.purpleAccent,
                  label: '4. Último Pedido de "Esqueci minha senha"',
                  value: _formatDateTime(auth['recovery_sent_at']),
                  textColor: textColor,
                ),
                Divider(color: borderColor, height: 20),
                _buildTimelineRow(
                  icon: Icons.login_rounded,
                  color: Colors.teal,
                  label: '5. Último Login Direto (last_sign_in_at)',
                  value: _formatDateTime(auth['last_sign_in_at']),
                  textColor: textColor,
                ),
                Divider(color: borderColor, height: 20),
                _buildTimelineRow(
                  icon: Icons.update_rounded,
                  color: Colors.blueGrey,
                  label: '6. Última Atualização no Auth',
                  value: _formatDateTime(auth['updated_at']),
                  textColor: textColor,
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // 5. Provedores / Identidades Vinculadas
          Text(
            'MÉTODOS DE LOGIN VINCULADOS (AUTH.IDENTITIES)',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          if (_identities.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Text(
                _loadingDetails
                    ? 'Carregando identidades...'
                    : 'Provedores ativos: ${_providers.isEmpty ? "Nenhum identificado" : _providers.join(", ").toUpperCase()}',
                style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 12.5),
              ),
            )
          else
            Column(
              children: _identities.map((ident) {
                final prov = (ident['provider'] ?? 'desconhecido').toString().toUpperCase();
                final isGoogle = prov == 'GOOGLE';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (isGoogle ? const Color(0xFF4285F4) : Colors.teal)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isGoogle ? Icons.g_mobiledata_rounded : Icons.email_outlined,
                          color: isGoogle ? const Color(0xFF4285F4) : Colors.teal,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Provedor: $prov',
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Vinculado em: ${_formatDateTime(ident['created_at'])}  •  Último login: ${_formatDateTime(ident['last_sign_in_at'])}',
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),

          // 6. Últimos E-mails no Resend (se houver)
          if (recentEmails.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              'ÚLTIMOS E-MAILS DISPARADOS PARA ESTE ENDEREÇO (RESEND)',
              style: TextStyle(
                color: textColor.withValues(alpha: 0.55),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            ...recentEmails.map((em) {
              final subject = (em['subject'] ?? 'Sem assunto').toString();
              final lastEvent = (em['last_event'] ?? 'sent').toString();
              final createdAt = _formatDateTime(em['created_at']);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.outbox_rounded,
                      size: 18,
                      color: Color(0xFF4F8EF7),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subject,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Data: $createdAt  •  Status Resend: ${lastEvent.toUpperCase()}',
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.6),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildMovementsTable(
    ColorScheme cs,
    Color cardColor,
    Color textColor,
    Color borderColor,
  ) {
    final movements = _getMovementsList();
    if (movements.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          _loadingDetails
              ? 'Carregando histórico de movimentos...'
              : 'Nenhum movimento registrado.',
          style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 12.5),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobileTable = constraints.maxWidth < 580;

        return Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            children: [
              // Cabeçalho da Tabela (apenas em telas largas)
              if (!isMobileTable) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.04),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 165,
                        child: Text(
                          'DATA E HORA',
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.6),
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 105,
                        child: Text(
                          'TIPO',
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.6),
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'MOVIMENTO / DETALHES NA PLATAFORMA',
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.6),
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: borderColor, height: 1),
              ],

              // Linhas da Tabela (responsivas para não dar overflow nunca)
              ...movements.asMap().entries.map((entry) {
                final idx = entry.key;
                final mov = entry.value;
                final category =
                    (mov['category'] ?? 'EVENTO').toString().toUpperCase();
                final title = (mov['title'] ?? '').toString();
                final details = (mov['details'] ?? '').toString();
                final catColor = _getCategoryColor(category);
                final dateStr = _formatDateTime(mov['timestamp']);

                if (isMobileTable) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (idx > 0) Divider(color: borderColor, height: 1),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: catColor.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: catColor.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Text(
                                    category,
                                    style: TextStyle(
                                      color: catColor,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  dateStr,
                                  style: TextStyle(
                                    color: textColor.withValues(alpha: 0.75),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              title,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (details.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                details,
                                style: TextStyle(
                                  color: textColor.withValues(alpha: 0.65),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    if (idx > 0) Divider(color: borderColor, height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 165,
                            child: Text(
                              dateStr,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 105,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: catColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: catColor.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  category,
                                  style: TextStyle(
                                    color: catColor,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (details.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    details,
                                    style: TextStyle(
                                      color: textColor.withValues(alpha: 0.65),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimelineRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required Color textColor,
  }) {
    final isMissing =
        value.startsWith('Não registrado') || value.startsWith('PENDENTE');
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 460) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 17, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.75),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 25, top: 4),
                child: Text(
                  value,
                  style: TextStyle(
                    color: isMissing ? textColor.withValues(alpha: 0.4) : textColor,
                    fontWeight: isMissing ? FontWeight.normal : FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.75),
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: isMissing ? textColor.withValues(alpha: 0.4) : textColor,
                  fontWeight: isMissing ? FontWeight.normal : FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // ABA 2: RESUMO DE ATIVIDADE, LOJAS E AGENDAMENTOS
  // ===========================================================================
  Widget _buildActivityTab(
    ColorScheme cs,
    Color cardColor,
    Color textColor,
    Color borderColor,
    double horizontalPad,
  ) {
    if (_loadingDetails) {
      return const Center(child: CircularProgressIndicator());
    }

    final activity = _fullDiag['activity'] is Map
        ? Map<String, dynamic>.from(_fullDiag['activity'] as Map)
        : <String, dynamic>{};
    final recentAppts = _fullDiag['recent_appointments'] is List
        ? (_fullDiag['recent_appointments'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
        : <Map<String, dynamic>>[];
    final linkedShops = _fullDiag['linked_shops'] is List
        ? (_fullDiag['linked_shops'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
        : <Map<String, dynamic>>[];

    final totalAppts = activity['total_appointments'] ?? 0;
    final confirmedAppts = activity['confirmed_or_completed'] ?? 0;
    final cancelledAppts = activity['cancelled'] ?? 0;
    final totalPaid = (activity['total_paid'] ?? 0).toDouble();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontalPad, 4, horizontalPad, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPIs de atividade responsivos (Grid/Wrap sem overflow)
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth > 720
                  ? 4
                  : (constraints.maxWidth > 420 ? 2 : 1);
              final spacing = 12.0;
              final itemWidth =
                  (constraints.maxWidth - (spacing * (cols - 1))) / cols;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _buildMiniStatCard(
                      'Total Agendamentos',
                      '$totalAppts',
                      Icons.calendar_today_rounded,
                      const Color(0xFF4F8EF7),
                      cardColor,
                      textColor,
                      borderColor,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildMiniStatCard(
                      'Confirmados / Concluídos',
                      '$confirmedAppts',
                      Icons.check_circle_outline_rounded,
                      const Color(0xFF16A34A),
                      cardColor,
                      textColor,
                      borderColor,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildMiniStatCard(
                      'Cancelados',
                      '$cancelledAppts',
                      Icons.cancel_outlined,
                      Colors.redAccent,
                      cardColor,
                      textColor,
                      borderColor,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildMiniStatCard(
                      'Total Movimentado',
                      'R\$ ${totalPaid.toStringAsFixed(2)}',
                      Icons.payments_outlined,
                      Colors.amber,
                      cardColor,
                      textColor,
                      borderColor,
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 22),

          // Lojas vinculadas
          Text(
            'LOJAS VINCULADAS (${linkedShops.length})',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          if (linkedShops.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Text(
                'Nenhuma loja vinculada até o momento.',
                style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 12.5),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: linkedShops.map((shop) {
                final isOwner = shop['relation'] == 'owner';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOwner ? Icons.storefront_rounded : Icons.favorite_border_rounded,
                        size: 16,
                        color: isOwner ? cs.primary : Colors.teal,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${shop['name'] ?? shop['id']} (${isOwner ? 'DONO' : 'CLIENTE'})',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),

          const SizedBox(height: 22),

          // Últimos Agendamentos
          Text(
            'HISTÓRICO DE AGENDAMENTOS DO CLIENTE',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          if (recentAppts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Text(
                'Este cliente ainda não possui agendamentos registrados.',
                style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 12.5),
              ),
            )
          else
            ...recentAppts.map((a) {
              final status = (a['status'] ?? '').toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_note_rounded, color: cs.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${a['service_name'] ?? 'Serviço'} — ${a['shop_name'] ?? a['shop_id']}',
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Data agendada: ${_formatDateTime(a['scheduled_at'])}  •  Status: ${status.toUpperCase()}  •  Pago: R\$ ${a['paid_amount'] ?? 0}',
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildMiniStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
    Color cardColor,
    Color textColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.55),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ABA 3: DADOS CADASTRAIS COMPLETOS E EDIÇÃO
  // ===========================================================================
  Widget _buildProfileEditTab(
    ColorScheme cs,
    Color cardColor,
    Color textColor,
    Color borderColor,
    String id,
    double horizontalPad,
  ) {
    final addressParts = [
      _userData['street'],
      _userData['number'],
      _userData['neighborhood'],
      _userData['city'],
      _userData['state'],
      _userData['zip_code'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).join(', ');

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontalPad, 4, horizontalPad, 32),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_isEditingProfile) ...[
              _buildDetailRow('UID (Supabase)', id, Icons.vpn_key_outlined, textColor),
              _buildDetailRow(
                'Telefone / WhatsApp',
                (_userData['phone'] ?? 'Não informado').toString(),
                Icons.phone_outlined,
                textColor,
              ),
              _buildDetailRow(
                'CPF / Documento',
                (_userData['cpf'] ??
                        _userData['documento'] ??
                        _userData['document_cpf'] ??
                        'Não informado')
                    .toString(),
                Icons.badge_outlined,
                textColor,
              ),
              _buildDetailRow(
                'Data de Nascimento',
                (_userData['birth_date'] ?? 'Não informada').toString(),
                Icons.cake_outlined,
                textColor,
              ),
              _buildDetailRow(
                'Endereço Cadastrado',
                addressParts.isEmpty ? 'Não informado' : addressParts,
                Icons.location_on_outlined,
                textColor,
              ),
              _buildDetailRow(
                'Tipo / Plano',
                '${(_userData['role'] ?? 'cliente').toString().toUpperCase()}  •  Plano: ${(_userData['plan'] ?? 'free').toString().toUpperCase()}',
                Icons.person_outline,
                textColor,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _isEditingProfile = true),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text(
                      'EDITAR DADOS CADASTRAIS',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.primary,
                      side: BorderSide(color: cs.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showRawData,
                    icon: Icon(
                      Icons.code,
                      color: textColor.withValues(alpha: 0.7),
                      size: 16,
                    ),
                    label: Text(
                      'VER JSON COMPLETO',
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor.withValues(alpha: 0.7),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: borderColor),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _deleteUser,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                      size: 16,
                    ),
                    label: const Text(
                      'EXCLUIR USUÁRIO',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              _buildEditField('Nome Completo', _nomeController, textColor),
              _buildEditField('E-mail', _emailController, textColor),
              _buildEditField('Telefone', _telefoneController, textColor),
              _buildEditField('CPF/CNPJ', _documentoController, textColor),
              _buildEditField('Cidade', _cidadeController, textColor),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                dropdownColor: cs.surface,
                initialValue: _currentTipo,
                style: TextStyle(color: textColor, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Tipo de Conta',
                  labelStyle: TextStyle(
                    color: textColor.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: borderColor),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'cliente', child: Text('Cliente')),
                  DropdownMenuItem(value: 'dono', child: Text('Dono de Negócio')),
                  DropdownMenuItem(value: 'admin', child: Text('Administrador')),
                  DropdownMenuItem(value: 'business', child: Text('Business')),
                  DropdownMenuItem(value: 'funcionario', child: Text('Funcionário')),
                ],
                onChanged: (val) => setState(() => _currentTipo = val),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _isEditingProfile = false),
                    child: Text(
                      'CANCELAR',
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        await Supabase.instance.client.from('users').update({
                          'name': _nomeController.text.trim(),
                          'email': _emailController.text.trim(),
                          'phone': _telefoneController.text.trim(),
                          'cpf': _documentoController.text.trim(),
                          'city': _cidadeController.text.trim(),
                          'role': _currentTipo,
                        }).eq('id', id);

                        setState(() => _isEditingProfile = false);
                        await _fetchDiagnostics();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Usuário atualizado com sucesso!')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erro ao atualizar: $e')),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'SALVAR ALTERAÇÕES',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon, Color textColor) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary.withValues(alpha: 0.7)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.45),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: TextStyle(color: textColor, fontSize: 13.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditField(
    String label,
    TextEditingController controller,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        style: TextStyle(color: textColor, fontSize: 13.5),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 11.5),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: textColor.withValues(alpha: 0.1)),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF4F8EF7)),
          ),
        ),
      ),
    );
  }

  Future<void> _showRawData() async {
    final theme = Theme.of(context);
    final combined = {
      'profile': _userData,
      'diagnostics': _fullDiag,
    };
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardColor,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'JSON Completo (Auth + Profile + Atividade)',
          style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 16),
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(combined),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: Colors.greenAccent,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('FECHAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser() async {
    final id = (_userData['id'] ?? '').toString();
    final nome = (_userData['name'] ?? 'este usuário').toString();
    final theme = Theme.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardColor,
        surfaceTintColor: Colors.transparent,
        title: const Text('Excluir Usuário?'),
        content: Text(
          'Tem certeza que deseja excluir permanentemente o usuário "$nome"? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'CANCELAR',
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color?.withValues(alpha: 0.5),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client.from('users').delete().eq('id', id);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuário excluído com sucesso.')),
        );
      }
    }
  }
}

class _DiagnosticInsight {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _DiagnosticInsight({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });
}
