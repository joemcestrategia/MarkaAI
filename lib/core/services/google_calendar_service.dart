import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Serviço para integração com Google Calendar
/// Permite backup e sincronização de agendamentos
class GoogleCalendarService {
  static const List<String> _scopes = [
    calendar.CalendarApi.calendarScope,
  ];


  /// Inicia o fluxo de autenticação OAuth2 usando o plugin nativo google_sign_in
  static Future<Map<String, dynamic>?> authenticateUser() async {
    try {
      final googleSignIn = GoogleSignIn(scopes: _scopes);

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

        await supabase.from('users').update({'googleCalendar': calendarData}).eq('id', user.id);

        return {
          'accessToken': gAuth.accessToken,
          'idToken': gAuth.idToken,
        };
      }

      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao autenticar com Google Calendar: $e');
      return null;
    }
  }

  /// Desconecta do Google Calendar
  static Future<void> disconnect() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user != null) {
      await supabase.from('users').update({
        'googleCalendar': null,
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
        .select('googleCalendar')
        .eq('id', user.id)
        .maybeSingle();

    if (doc == null) return false;
    final data = doc['googleCalendar'] as Map<String, dynamic>?;
    return data?['connected'] ?? false;
  }
}
