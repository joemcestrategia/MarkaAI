import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'web_auth_interop_stub.dart' if (dart.library.js_interop) 'web_auth_interop_web.dart';

/// Serviço para integração com Google Calendar
/// Permite backup e sincronização de agendamentos
class GoogleCalendarService {
  static const List<String> _scopes = [
    calendar.CalendarApi.calendarScope,
  ];

  static GoogleSignIn? _googleSignIn;

  static void _log(String message) {
    debugPrint('[GoogleCalendar] $message');
  }

  static void _logError(String message, Object error, [StackTrace? stack]) {
    debugPrint('[GoogleCalendar] ERROR - $message: $error');
    if (stack != null) debugPrint('[GoogleCalendar] STACK: $stack');
  }

  static GoogleSignIn _getSignIn() {
    _googleSignIn ??= GoogleSignIn(
      scopes: _scopes,
      forceCodeForRefreshToken: true,
      // Web client ID usado para trocar auth code por refresh token no servidor
      serverClientId: '170942564821-s8doqh3tcqe4rs7muauefgkdqehcf1l9.apps.googleusercontent.com',
    );
    return _googleSignIn!;
  }

  /// Inicia o fluxo de autenticação OAuth2 usando o plugin nativo google_sign_in
  /// Retorna null se falhar/cancelar; caso contrário mapa com tokens e dados do usuário
  static Future<Map<String, dynamic>> authenticateUser({String? employeeId}) async {
    _log('Iniciando autenticação Google Calendar...');
    try {
      _log('Scopes solicitados: $_scopes');
      
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null && employeeId == null) {
        _logError('Usuário Supabase é null — não autenticado no Supabase', Exception('supabaseUser null'));
        return {'success': false, 'error': 'Usuário não autenticado. Faça login novamente.'};
      }

      String? accessToken;
      String? idToken;
      String? serverAuthCode;
      String? email = 'Sua Conta Google (Web)';
      String? displayName = 'Usuário (Web)';

      if (kIsWeb) {
        _log('Web: Acionando GIS initCodeClient (sem waits prévios que quebram o popup)...');
        serverAuthCode = await getGoogleAuthCodeWeb(
          '170942564821-s8doqh3tcqe4rs7muauefgkdqehcf1l9.apps.googleusercontent.com',
          _scopes.first,
        );

        if (serverAuthCode == null || serverAuthCode.isEmpty) {
          return {'success': false, 'error': 'Permissão de acesso ao Google Calendar cancelada ou negada.'};
        }
        accessToken = 'gis_web_flow'; // placeholder seguro
      } else {
        // Fluxo nativo (Android/iOS)
        final googleSignIn = _getSignIn();

        _log('Verificando se já está logado no Google Sign-In...');
        final alreadySignedIn = await googleSignIn.isSignedIn();
        if (alreadySignedIn) {
          _log('Já estava logado, fazendo disconnect para revogar consentimento e forçar nova seleção...');
          try {
            await googleSignIn.disconnect();
          } catch (e) {
            _log('Erro no disconnect, fazendo signOut fallback: $e');
            await googleSignIn.signOut();
          }
        } else {
          try { await googleSignIn.signOut(); } catch (_) {}
        }

        _log('Chamando googleSignIn.signIn() — abrindo seletor de conta...');
        final GoogleSignInAccount? gUser = await googleSignIn.signIn();
        if (gUser == null) {
          _log('Usuário cancelou o login ou retornou null');
          return {'success': false, 'error': 'Seleção de conta cancelada pelo usuário.'};
        }

        final GoogleSignInAuthentication gAuth = await gUser.authentication;
        serverAuthCode = gUser.serverAuthCode;
        accessToken = gAuth.accessToken;
        idToken = gAuth.idToken;
        email = gUser.email;
        displayName = gUser.displayName;

        if (accessToken == null) {
          _logError('accessToken veio null', Exception('accessToken null'));
          return {'success': false, 'error': 'Permissão do Google Calendar não concedida. Verifique os escopos.'};
        }
      }

      final calendarData = {
        'connected': true,
        'accessToken': accessToken,
        'idToken': idToken,
        'expiry': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
        'connectedAt': DateTime.now().toIso8601String(),
        'email': email,
        'displayName': displayName,
      };

      _log('Salvando dados de conexão via Edge Function (bypass RLS)...');
      try {
        final edgeBody = <String, dynamic>{
          'calendarData': calendarData,
        };
        
        if (kIsWeb) {
          edgeBody['platform'] = 'web';
        }

        if (employeeId != null) {
          edgeBody['employeeId'] = employeeId;
        } else if (user != null) {
          edgeBody['userId'] = user.id;
        }

        if (serverAuthCode != null && serverAuthCode.isNotEmpty) {
          edgeBody['serverAuthCode'] = serverAuthCode;
          _log('Enviando serverAuthCode para troca por refresh token no servidor...');
        }

        final saveResponse = await supabase.functions.invoke('save-google-calendar', body: edgeBody);

        _log('Edge Function response: status=${saveResponse.status}');

        if (saveResponse.status != 200) {
          final errData = saveResponse.data;
          final errMsg = errData is Map ? (errData['error'] ?? errData.toString()) : errData.toString();
          _logError('Edge Function retornou erro $errMsg', Exception('edgeFunction failed'));
          return {'success': false, 'error': errMsg};
        }

        final responseData = saveResponse.data as Map<String, dynamic>?;
        if (responseData?['success'] != true) {
          final errMsg = responseData?['error'] ?? 'Erro desconhecido do servidor';
          _logError('Edge Function não confirmou sucesso: $errMsg', Exception('success != true'));
          return {'success': false, 'error': errMsg};
        }

        _log('Update via Edge Function OK — email=${responseData?['email']}, hasRefreshToken=${responseData?['hasRefreshToken']}');
      } catch (dbError, stack) {
        _logError('Erro ao chamar Edge Function save-google-calendar', dbError, stack);
        return {'success': false, 'error': 'Erro de rede ao salvar no servidor: $dbError'};
      }

      _log('Autenticação Google Calendar concluída com sucesso!');
      return {
        'success': true,
        'accessToken': accessToken,
        'email': email,
        'displayName': displayName,
      };
    } catch (e, stack) {
      _logError('Erro ao autenticar com Google Calendar', e, stack);
      final msg = e.toString();
      if (msg.contains('PlatformException')) {
        _logError('PlatformException detectada — possível erro de configuração nativa do google_sign_in', e);
        return {'success': false, 'error': 'Erro de configuração do Google Sign-In. Verifique a impressão digital SHA-1 no Firebase Console e o google-services.json.'};
      }
      if (msg.contains('sign_in_failed') || msg.contains('SIGN_IN_FAILED')) {
        _logError('Google Sign-In falhou — verifique firebase/google-services.json e OAuth consent screen', e);
        return {'success': false, 'error': 'Google Sign-In falhou. Verifique firebase/google-services.json e a tela de consentimento OAuth no Google Cloud Console.'};
      }
      if (msg.contains('invalid_scope') || msg.contains('access_denied')) {
        _logError('Escopo do Calendar negado! Verifique se https://www.googleapis.com/auth/calendar está no OAuth consent screen', e);
        return {'success': false, 'error': 'Escopo do Google Calendar negado. Adicione o escopo calendar no OAuth consent screen do Google Cloud Console.'};
      }
      return {'success': false, 'error': msg};
    }
  }

  /// Sincroniza agendamentos com Google Calendar: cria, atualiza e deleta.
  /// [toCreate]: agendamentos sem google_calendar_event_id (cria novo evento)
  /// [toUpdate]: agendamentos já sincronizados que precisam ser atualizados
  /// [eventIdsToDelete]: IDs de eventos Google Calendar de agendamentos cancelados
  /// [onProgress]: callback (message, current, total) para UI mostrar progresso
  /// Retorna mapa com contadores: created, updated, deleted
  /// Resultado do syncAll inclui contadores e lista de falhas
  /// Retorna: { 'created': int, 'updated': int, 'deleted': int, 'failures': List<Map<String, dynamic>> }
  /// Cada falha: { 'id': String, 'client_name': String, 'service_name': String, 'scheduled_at': String?, 'error': String }
  static Future<Map<String, dynamic>> syncAll({
    required List<Map<String, dynamic>> toCreate,
    required List<Map<String, dynamic>> toUpdate,
    required List<String> eventIdsToDelete,
    required String shopName,
    String eventIdCol = 'google_calendar_event_id',
    String? employeeId,
    void Function(String message, int current, int total)? onProgress,
  }) async {
    final counters = <String, dynamic>{'created': 0, 'updated': 0, 'deleted': 0, 'failures': <Map<String, dynamic>>[]};
    final failures = counters['failures'] as List<Map<String, dynamic>>;
    final total = toCreate.length + toUpdate.length + eventIdsToDelete.length;
    if (total == 0) return counters;

    _log('Iniciando syncAll: criar=${toCreate.length} atualizar=${toUpdate.length} deletar=${eventIdsToDelete.length}');
    try {
      final supabase = Supabase.instance.client;
      String? accessToken;

      if (employeeId != null || supabase.auth.currentUser != null) {
        _log('Tentando renovar token via edge function (Modo backend)...');
        try {
          final bodyParams = <String, dynamic>{'action': 'refresh'};
          if (employeeId != null) {
            bodyParams['employeeId'] = employeeId;
          } else {
            bodyParams['userId'] = supabase.auth.currentUser!.id;
          }

          final refreshRes = await supabase.functions.invoke('save-google-calendar', body: bodyParams);

          final data = refreshRes.data as Map<String, dynamic>?;
          if (refreshRes.status == 200 && data?['success'] == true && data?['accessToken'] != null) {
            accessToken = data!['accessToken'] as String;
            _log('Token renovado com sucesso via backend');
          } else {
            final errMsg = data?['error'] as String? ?? 'Edge function não retornou accessToken';
            _log('Falha ao renovar token via backend: $errMsg (status=${refreshRes.status})');
          }
        } catch (e, stack) {
          _logError('Erro ao renovar token via backend', e, stack);
        }
      }

      if (accessToken == null && employeeId == null) {
        if (kIsWeb) {
          _log('Fallback: Modo Web ignorado para signInSilently. Necessária reautenticação explícita pelo usuário.');
          counters['error'] = 'Token expirado. Por favor, conecte a conta novamente.';
          return counters;
        }

        // Fallback para o modo owner: usa Google Sign-In do dispositivo apenas se falhou via edge function
        _log('Fallback: Modo owner, usando Google Sign-In do dispositivo...');
        final googleSignIn = _getSignIn();
        GoogleSignInAccount? gUser = await googleSignIn.signInSilently();
        gUser ??= await googleSignIn.signIn();
        if (gUser == null) {
          _logError('Nenhuma conta Google disponível e usuário cancelou o prompt', Exception('gUser null'));
          return counters;
        }

        final gAuth = await gUser.authentication;
        if (gAuth.accessToken == null) {
          _logError('accessToken null', Exception('accessToken null'));
          return counters;
        }

        accessToken = gAuth.accessToken;
      }

      if (accessToken == null) {
         _logError('Não foi possível obter token de acesso (nem via backend, nem via fallback local)', Exception('no token'));
         return counters;
      }

      final credentials = auth.AccessCredentials(
        auth.AccessToken('Bearer', accessToken!, DateTime.now().add(const Duration(hours: 1)).toUtc()),
        null,
        _scopes,
      );
      final httpClient = auth.authenticatedClient(http.Client(), credentials);
      final calendarApi = calendar.CalendarApi(httpClient);

      int step = 0;

      // 1. Criar novos eventos (com detecção de duplicatas)
      for (int i = 0; i < toCreate.length; i++) {
        final appt = toCreate[i];
        step++;
        onProgress?.call('Criando', step, total);
        try {
          final event = _buildCalendarEvent(appt, shopName);

          // Busca duplicatas no Google Calendar antes de criar
          final startRfc = appt['scheduled_at'] as String?;
          if (startRfc != null) {
            final startUtc = DateTime.tryParse(startRfc)?.toUtc() ?? DateTime.now().toUtc();
            // Amplia a janela de busca para +/- 12 horas para capturar agendamentos que mudaram de horário
            final timeMin = startUtc.subtract(const Duration(hours: 12)).toUtc();
            final timeMax = startUtc.add(const Duration(hours: 12)).toUtc();
            try {
              calendar.Event? match;
              // Barreira 1: Busca pelo ID Oculto (Identidade MarkaAI)
              if (appt['id'] != null) {
                try {
                  final existingById = await calendarApi.events.list(
                    'primary',
                    privateExtendedProperty: ['markaai_appointment_id=${appt['id']}'],
                    singleEvents: true,
                  );
                  if (existingById.items != null && existingById.items!.isNotEmpty) {
                    match = existingById.items!.first;
                  }
                } catch (_) {}
              }

              // Barreira 2: Fallback por Horário + Nome (para eventos antigos)
              if (match == null) {
                final existing = await calendarApi.events.list(
                  'primary',
                  timeMin: timeMin,
                  timeMax: timeMax,
                  q: event.summary,
                  singleEvents: true,
                  maxResults: 10,
                );
                match = existing.items?.firstWhere(
                  (item) => item.summary == event.summary,
                  orElse: () => calendar.Event(),
                );
              }

              if (match != null && match.id != null) {
                // Duplicata encontrada, atualiza ao invés de criar
                await calendarApi.events.update(event, 'primary', match.id!);
                if (appt['id'] != null) {
                  await supabase.from('appointments').update({eventIdCol: match.id}).eq('id', appt['id']);
                }
                counters['created'] = (counters['created'] as int) + 1;
                _log('  Duplicata detectada, atualizado: ${appt['client_name']} → eventId=${match.id}');
                continue;
              }
            } catch (_) {
              // Se a busca falhar, prossegue com a criação normalmente
            }
          }

          final created = await calendarApi.events.insert(event, 'primary');
          if (created.id != null && appt['id'] != null) {
            await supabase.from('appointments').update({
              eventIdCol: created.id,
            }).eq('id', appt['id']);
            counters['created'] = (counters['created'] as int) + 1;
            _log('  Criado: ${appt['client_name']} → eventId=${created.id}');
          }
        } catch (e, stack) {
          _logError('Falha ao criar evento para ${appt['id']}', e, stack);
          failures.add({
            'id': appt['id'],
            'client_name': appt['client_name'] ?? 'Cliente',
            'service_name': appt['service_name'] ?? 'Serviço',
            'scheduled_at': appt['scheduled_at'],
            'error': _friendlyError(e.toString()),
          });
        }
      }

      // 2. Atualizar eventos existentes (com fallback para 404 → recriar)
      for (int i = 0; i < toUpdate.length; i++) {
        final appt = toUpdate[i];
        step++;
        onProgress?.call('Atualizando', step, total);
        try {
          final eventId = appt[eventIdCol] as String?;
          if (eventId == null || eventId.isEmpty) continue;
          final event = _buildCalendarEvent(appt, shopName);
          try {
            await calendarApi.events.update(event, 'primary', eventId);
            counters['updated'] = (counters['updated'] as int) + 1;
            _log('  Atualizado: ${appt['client_name']} → eventId=$eventId');
          } catch (updateError) {
            // Se o evento não existe mais no Google (404), recria
            if (_isNotFound(updateError.toString())) {
              final created = await calendarApi.events.insert(event, 'primary');
              if (created.id != null && appt['id'] != null) {
                await supabase.from('appointments').update({eventIdCol: created.id}).eq('id', appt['id']);
              }
              counters['updated'] = (counters['updated'] as int) + 1;
              _log('  Recriado (404): ${appt['client_name']} → eventId=${created.id}');
            } else {
              rethrow;
            }
          }
        } catch (e, stack) {
          _logError('Falha ao atualizar evento para ${appt['id']}', e, stack);
          failures.add({
            'id': appt['id'],
            'client_name': appt['client_name'] ?? 'Cliente',
            'service_name': appt['service_name'] ?? 'Serviço',
            'scheduled_at': appt['scheduled_at'],
            'error': _friendlyError(e.toString()),
          });
        }
      }

      // 3. Deletar eventos cancelados
      for (int i = 0; i < eventIdsToDelete.length; i++) {
        final eventId = eventIdsToDelete[i];
        step++;
        onProgress?.call('Removendo', step, total);
        try {
          await calendarApi.events.delete('primary', eventId);
          counters['deleted'] = (counters['deleted'] as int) + 1;
          _log('  Deletado: eventId=$eventId');
        } catch (e, stack) {
          _logError('Falha ao deletar evento $eventId', e, stack);
        }
      }

      // 4. Limpeza de Órfãos
      try {
        onProgress?.call('Limpando órfãos...', step, total);
        final activeAppts = [...toCreate, ...toUpdate];
        final orphansDeleted = await _cleanupOrphans(calendarApi, activeAppts, eventIdCol);
        counters['deleted'] = (counters['deleted'] as int) + orphansDeleted;
        if (orphansDeleted > 0) _log('  Órfãos removidos: $orphansDeleted');
      } catch (e) {
        _logError('Falha ao limpar órfãos', e);
      }

      httpClient.close();
      _log('syncAll concluído: created=${counters['created']}, updated=${counters['updated']}, deleted=${counters['deleted']}, failures=${failures.length}');

      // Atualiza lastSync
      await _updateLastSync(supabase, employeeId: employeeId);

      return counters;
    } catch (e, stack) {
      _logError('Erro no syncAll', e, stack);
      return counters;
    }
  }

  static Future<int> _cleanupOrphans(
      calendar.CalendarApi calendarApi,
      List<Map<String, dynamic>> activeAppointments,
      String eventIdCol) async {
    int deleted = 0;
    try {
      // Busca eventos futuros (de ontem em diante) com a marca registrada
      final timeMin = DateTime.now().subtract(const Duration(days: 1)).toUtc();
      
      final res = await calendarApi.events.list(
        'primary',
        timeMin: timeMin,
        q: 'Agendamento via MarkaAI',
        singleEvents: true,
        maxResults: 2500,
      );
      
      final items = res.items ?? [];
      
      final activeApptIds = activeAppointments.map((a) => a['id'].toString()).toSet();
      final activeEventIds = activeAppointments
          .map((a) => a[eventIdCol] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .toSet();

      for (final item in items) {
        if (item.id == null) continue;
        
        bool isMarkaAI = false;
        String? markaaiId = item.extendedProperties?.private?['markaai_appointment_id'];
        
        if (markaaiId != null && markaaiId.isNotEmpty) {
          isMarkaAI = true;
        } else if (item.description != null && item.description!.contains('Agendamento via MarkaAI')) {
          isMarkaAI = true;
        }
        
        if (!isMarkaAI) continue;
        
        bool isActive = false;
        if (markaaiId != null && activeApptIds.contains(markaaiId)) {
          isActive = true;
        }
        if (activeEventIds.contains(item.id)) {
          isActive = true;
        }
        
        if (!isActive) {
          // É um órfão: foi criado pelo MarkaAI mas não está na lista de ativos
          try {
            await calendarApi.events.delete('primary', item.id!);
            deleted++;
            _log('  Órfão deletado: ${item.summary} (eventId=${item.id})');
          } catch (_) {}
        }
      }
    } catch (e) {
      _logError('Erro em _cleanupOrphans', e);
    }
    return deleted;
  }

  /// Traduz erros técnicos do Google Calendar para mensagens amigáveis
  static String _friendlyError(String error) {
    if (error.contains('time range is empty')) {
      return 'Duração zero (horário início = fim)';
    }
    if (error.contains('401') || error.contains('Unauthorized')) {
      return 'Token expirado';
    }
    if (error.contains('403') || error.contains('Forbidden')) {
      return 'Sem permissão no calendário';
    }
    if (error.contains('404')) {
      return 'Evento não encontrado';
    }
    if (error.contains('Rate Limit') || error.contains('429')) {
      return 'Limite de requisições excedido';
    }
    return error.length > 80 ? '${error.substring(0, 80)}...' : error;
  }

  static bool _isNotFound(String error) {
    return error.contains('404') || error.contains('notFound') || error.contains('Not Found');
  }

  static Future<void> _updateLastSync(SupabaseClient supabase, {String? employeeId}) async {
    final user = supabase.auth.currentUser;
    if (user == null && employeeId == null) return;
    
    Map<String, dynamic> existing = {};
    if (employeeId != null) {
      final doc = await supabase.from('employees').select('google_calendar').eq('id', employeeId).maybeSingle();
      existing = Map<String, dynamic>.from((doc?['google_calendar'] as Map?) ?? {});
    } else if (user != null) {
      final doc = await supabase.from('users').select('google_calendar').eq('id', user.id).maybeSingle();
      existing = Map<String, dynamic>.from((doc?['google_calendar'] as Map?) ?? {});
    }

    existing['lastSync'] = DateTime.now().toIso8601String();
    
    try {
      final edgeBody = <String, dynamic>{
        'calendarData': existing,
      };
      if (employeeId != null) edgeBody['employeeId'] = employeeId;
      else if (user != null) edgeBody['userId'] = user.id;

      await supabase.functions.invoke('save-google-calendar', body: edgeBody);
    } catch (_) {
      if (employeeId != null) {
        await supabase.from('employees').update({'google_calendar': existing}).eq('id', employeeId);
      } else if (user != null) {
        await supabase.from('users').update({'google_calendar': existing}).eq('id', user.id);
      }
    }
    _log('lastSync atualizado');
  }

  /// Extrai o horário de parede para envio ao Google Calendar.
  /// Os valores no banco (TIMESTAMPTZ+00) já representam a hora local de SP,
  /// portanto não é necessária conversão de timezone.
  static DateTime _toSaoPauloWallClock(DateTime utc) {
    final trueUtc = utc.toUtc();
    return DateTime(trueUtc.year, trueUtc.month, trueUtc.day, trueUtc.hour, trueUtc.minute, trueUtc.second);
  }

  /// Constrói um [calendar.Event] a partir de um mapa de agendamento
  static calendar.Event _buildCalendarEvent(
      Map<String, dynamic> appt, String shopName) {
    final scheduledAtRaw = appt['scheduled_at'] as String?;
    final endAtRaw = appt['end_at'] as String?;

    DateTime startUtc = scheduledAtRaw != null
        ? (DateTime.tryParse(scheduledAtRaw) ?? DateTime.now().toUtc())
        : DateTime.now().toUtc();
    // Ignora completamente o `end_at` do banco para evitar bugs de extensão de dias
    // e sempre calcula dinamicamente baseado na duração real (duration_min)
    final durationMin = (appt['duration_min'] as num?)?.toInt() ?? 60;
    DateTime endUtc = startUtc.add(Duration(minutes: durationMin));

    // Garante duração mínima para evitar "The specified time range is empty"
    if (!endUtc.isAfter(startUtc)) {
      final durationMin = (appt['duration_min'] as num?)?.toInt();
      final fallback = (durationMin != null && durationMin > 0) ? durationMin : 30;
      endUtc = startUtc.add(Duration(minutes: fallback));
    }

    // Converte para horário de parede de São Paulo
    final startSp = _toSaoPauloWallClock(startUtc.toUtc());
    final endSp = _toSaoPauloWallClock(endUtc.toUtc());

    final clientName =
        (appt['client_name'] as String?)?.isNotEmpty == true
            ? appt['client_name'] as String
            : 'Cliente';
    final serviceName =
        (appt['service_name'] as String?)?.isNotEmpty == true
            ? appt['service_name'] as String
            : 'Serviço';
    final professionalName = appt['professional_name'] as String?;

    final description = [
      'Agendamento via MarkaAI',
      'Loja: $shopName',
      'Cliente: $clientName',
      if (professionalName != null && professionalName.isNotEmpty)
        'Profissional: $professionalName',
    ].join('\n');

    return calendar.Event(
      summary: '$serviceName — $clientName',
      description: description,
      start: calendar.EventDateTime(
        dateTime: startSp,
        timeZone: 'America/Sao_Paulo',
      ),
      end: calendar.EventDateTime(
        dateTime: endSp,
        timeZone: 'America/Sao_Paulo',
      ),
      reminders: calendar.EventReminders(
        useDefault: false,
        overrides: [
          calendar.EventReminder(method: 'popup', minutes: 60),
          calendar.EventReminder(method: 'popup', minutes: 15),
        ],
      ),
      extendedProperties: calendar.EventExtendedProperties(
        private: {
          'markaai_appointment_id': appt['id']?.toString() ?? '',
        },
      ),
    );
  }

  /// Desconecta do Google Calendar
  static Future<void> disconnect({String? employeeId}) async {
    _log('Desconectando do Google Calendar (employeeId=$employeeId)...');

    // Para profissionais, NÃO faz signOut do dispositivo — cada profissional
    // tem tokens independentes no Supabase. O signOut do dispositivo afetaria
    // o estado compartilhado do Google Sign-In, prejudicando outros profissionais.
    if (employeeId == null) {
      try {
        final googleSignIn = _getSignIn();
        if (await googleSignIn.isSignedIn()) {
          await googleSignIn.signOut();
          _log('SignOut do Google Sign-In OK (modo owner)');
        }
        _googleSignIn = null;
      } catch (e, stack) {
        _logError('Erro ao fazer signOut do Google', e, stack);
      }
    }

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user != null || employeeId != null) {
      // Usa Edge Function para garantir bypass da RLS
      try {
        final edgeBody = <String, dynamic>{
          'calendarData': null,
        };
        if (employeeId != null) {
          edgeBody['employeeId'] = employeeId;
        } else if (user != null) {
          edgeBody['userId'] = user.id;
        }

        await supabase.functions.invoke('save-google-calendar', body: edgeBody);
      } catch (_) {
        // Tenta fallback direto
        if (employeeId != null) {
          await supabase.from('employees').update({'google_calendar': null}).eq('id', employeeId);
        } else if (user != null) {
          await supabase.from('users').update({'google_calendar': null}).eq('id', user.id);
        }
      }
      _log('Dados google_calendar removidos do Supabase para ${employeeId ?? user?.id}');
    }
  }

  /// Verifica se o usuário está conectado ao Google Calendar
  static Future<bool> isConnected({String? employeeId}) async {
    _log('Verificando status de conexão Google Calendar...');
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null && employeeId == null) {
      _log('Usuário Supabase null e employeeId null — retornando false');
      return false;
    }

    Map<String, dynamic>? doc;
    if (employeeId != null) {
      doc = await supabase.from('employees').select('google_calendar').eq('id', employeeId).maybeSingle();
    } else if (user != null) {
      doc = await supabase.from('users').select('google_calendar').eq('id', user.id).maybeSingle();
    }

    if (doc == null) {
      _log('Documento do usuário/funcionário não encontrado');
      return false;
    }
    final data = doc['google_calendar'] as Map<String, dynamic>?;
    final connected = data?['connected'] ?? false;
    _log('Status de conexão: connected=$connected');
    return connected;
  }
}
