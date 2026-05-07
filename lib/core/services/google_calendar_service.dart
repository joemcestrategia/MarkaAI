import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Serviço para integração com Google Calendar
/// Permite backup e sincronização de agendamentos
class GoogleCalendarService {
  static const List<String> _scopes = [
    calendar.CalendarApi.calendarScope,
  ];

  static GoogleSignIn? _googleSignIn;

  static GoogleSignIn _getSignIn() {
    _googleSignIn ??= GoogleSignIn(scopes: _scopes);
    return _googleSignIn!;
  }

  /// Inicia o fluxo de autenticação OAuth2 usando o plugin nativo google_sign_in
  static Future<Map<String, dynamic>?> authenticateUser() async {
    try {
      final googleSignIn = _getSignIn();

      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }

      final GoogleSignInAccount? gUser = await googleSignIn.signIn();
      if (gUser == null) return null;

      final GoogleSignInAuthentication gAuth = await gUser.authentication;

      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      
      if (user != null) {
        final calendarData = {
          'connected': true,
          'accessToken': gAuth.accessToken,
          'idToken': gAuth.idToken,
          'expiry': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
          'connectedAt': DateTime.now().toIso8601String(),
          'email': gUser.email,
          'displayName': gUser.displayName,
        };

        await supabase.from('users').update({'google_calendar': calendarData}).eq('id', user.id);

        return {
          'accessToken': gAuth.accessToken,
          'email': gUser.email,
          'displayName': gUser.displayName,
        };
      }

      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao autenticar com Google Calendar: $e');
      return null;
    }
  }

  /// Sincroniza lista de agendamentos pendentes para o Google Calendar.
  /// Retorna o número de eventos criados com sucesso.
  static Future<int> syncAppointments({
    required List<Map<String, dynamic>> appointments,
    required String shopName,
  }) async {
    try {
      final googleSignIn = _getSignIn();

      // Tenta silent sign-in primeiro; senão pede interativo
      GoogleSignInAccount? gUser = await googleSignIn.signInSilently();
      gUser ??= await googleSignIn.signIn();
      if (gUser == null) return 0;

      final gAuth = await gUser.authentication;
      final accessToken = gAuth.accessToken;
      if (accessToken == null) return 0;

      // Cria cliente HTTP autenticado
      final credentials = auth.AccessCredentials(
        auth.AccessToken(
          'Bearer',
          accessToken,
          DateTime.now().add(const Duration(hours: 1)).toUtc(),
        ),
        null,
        _scopes,
      );
      final httpClient = auth.authenticatedClient(http.Client(), credentials);
      final calendarApi = calendar.CalendarApi(httpClient);

      final supabase = Supabase.instance.client;
      int synced = 0;

      for (final appt in appointments) {
        try {
          final event = _buildCalendarEvent(appt, shopName);
          final created = await calendarApi.events.insert(event, 'primary');

          if (created.id != null && appt['id'] != null) {
            await supabase
                .from('appointments')
                .update({'google_calendar_event_id': created.id})
                .eq('id', appt['id']);
            synced++;
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Erro ao sincronizar agendamento ${appt['id']}: $e');
        }
      }

      httpClient.close();

      // Atualiza lastSync no perfil do usuário
      final user = supabase.auth.currentUser;
      if (user != null) {
        final doc = await supabase
            .from('users')
            .select('google_calendar')
            .eq('id', user.id)
            .maybeSingle();
        final existing = Map<String, dynamic>.from(
            (doc?['google_calendar'] as Map?) ?? {});
        existing['lastSync'] = DateTime.now().toIso8601String();
        await supabase
            .from('users')
            .update({'google_calendar': existing})
            .eq('id', user.id);
      }

      return synced;
    } catch (e) {
      if (kDebugMode) debugPrint('Erro na sincronização com Google Calendar: $e');
      return 0;
    }
  }

  /// Constrói um [calendar.Event] a partir de um mapa de agendamento
  static calendar.Event _buildCalendarEvent(
      Map<String, dynamic> appt, String shopName) {
    final scheduledAtRaw = appt['scheduled_at'] as String?;
    final endAtRaw = appt['end_at'] as String?;

    DateTime start = scheduledAtRaw != null
        ? DateTime.tryParse(scheduledAtRaw) ?? DateTime.now()
        : DateTime.now();

    DateTime end;
    if (endAtRaw != null) {
      end = DateTime.tryParse(endAtRaw) ?? start.add(const Duration(hours: 1));
    } else {
      final durationMin = (appt['duration_min'] as num?)?.toInt() ?? 60;
      end = start.add(Duration(minutes: durationMin));
    }

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
        dateTime: start,
        timeZone: 'America/Sao_Paulo',
      ),
      end: calendar.EventDateTime(
        dateTime: end,
        timeZone: 'America/Sao_Paulo',
      ),
      reminders: calendar.EventReminders(
        useDefault: false,
        overrides: [
          calendar.EventReminder(method: 'popup', minutes: 60),
          calendar.EventReminder(method: 'popup', minutes: 15),
        ],
      ),
    );
  }

  /// Desconecta do Google Calendar
  static Future<void> disconnect() async {
    try {
      final googleSignIn = _getSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao fazer signOut do Google: $e');
    }

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user != null) {
      await supabase.from('users').update({
        'google_calendar': null,
      }).eq('id', user.id);
    }
  }

  /// Verifica se o usuário está conectado ao Google Calendar
  static Future<bool> isConnected() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    final doc = await supabase
        .from('users')
        .select('google_calendar')
        .eq('id', user.id)
        .maybeSingle();

    if (doc == null) return false;
    final data = doc['google_calendar'] as Map<String, dynamic>?;
    return data?['connected'] ?? false;
  }
}
