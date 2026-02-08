import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

/// Serviço para integração com Google Calendar
/// Permite backup e sincronização de agendamentos
class GoogleCalendarService {
  static const List<String> _scopes = [
    calendar.CalendarApi.calendarScope,
  ];

  // Nome do calendário de backup
  static const String _calendarName = 'MarkaAI - Agendamentos';
  
  /// Inicia o fluxo de autenticação OAuth2
  static Future<Map<String, dynamic>?> authenticateUser() async {
    try {
      // Credenciais OAuth2 do Google Cloud Console
      final clientId = ClientId(
        '439682458293-r1kmpqq7l8qr79m68acsrm5cbulnpkrq.apps.googleusercontent.com',
        '', // Client secret não é necessário para apps mobile
      );

      // Redireciona para autorização
      final client = await clientViaUserConsent(
        clientId,
        _scopes,
        (url) async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
      );

      // Salva tokens no Firestore
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final credentials = client.credentials;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
          'googleCalendar': {
            'connected': true,
            'accessToken': credentials.accessToken.data,
            'refreshToken': credentials.refreshToken,
            'expiry': credentials.accessToken.expiry.toIso8601String(),
            'connectedAt': FieldValue.serverTimestamp(),
          }
        }, SetOptions(merge: true));

        return {
          'accessToken': credentials.accessToken.data,
          'refreshToken': credentials.refreshToken,
          'expiry': credentials.accessToken.expiry.toIso8601String(),
        };
      }

      client.close();
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao autenticar com Google Calendar: $e');
      return null;
    }
  }

  /// Desconecta do Google Calendar
  static Future<void> disconnect() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'googleCalendar.connected': false,
        'googleCalendar.disconnectedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Verifica se o usuário está conectado ao Google Calendar
  static Future<bool> isConnected() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = doc.data();
    return data?['googleCalendar']?['connected'] ?? false;
  }

  /// Obtém o cliente autenticado do Google Calendar
  static Future<calendar.CalendarApi?> _getCalendarClient() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final calendarData = doc.data()?['googleCalendar'];
    if (calendarData == null || calendarData['connected'] != true) {
      return null;
    }

    try {
      final credentials = AccessCredentials(
        AccessToken(
          'Bearer',
          calendarData['accessToken'],
          DateTime.parse(calendarData['expiry']),
        ),
        calendarData['refreshToken'],
        _scopes,
      );

      final client = authenticatedClient(http.Client(), credentials);
      return calendar.CalendarApi(client);
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao obter cliente do Calendar: $e');
      return null;
    }
  }

  /// Encontra ou cria o calendário de backup do MarkaAI
  static Future<String?> _getOrCreateBackupCalendar() async {
    final calendarApi = await _getCalendarClient();
    if (calendarApi == null) return null;

    try {
      // Lista calendários existentes
      final calendarList = await calendarApi.calendarList.list();
      
      // Procura pelo calendário do MarkaAI
      for (var entry in calendarList.items ?? []) {
        if (entry.summary == _calendarName) {
          return entry.id;
        }
      }

      // Se não existe, cria um novo
      final newCalendar = calendar.Calendar()
        ..summary = _calendarName
        ..description = 'Backup automático dos agendamentos do MarkaAI'
        ..timeZone = 'America/Sao_Paulo';

      final created = await calendarApi.calendars.insert(newCalendar);
      return created.id;
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao criar/encontrar calendário: $e');
      return null;
    }
  }

  /// Cria ou atualiza um evento no Google Calendar
  static Future<bool> syncAppointment({
    required String appointmentId,
    required Map<String, dynamic> appointmentData,
  }) async {
    final calendarApi = await _getCalendarClient();
    if (calendarApi == null) return false;

    final calendarId = await _getOrCreateBackupCalendar();
    if (calendarId == null) return false;

    try {
      final dataAgendamento = (appointmentData['data_agendamento'] as Timestamp?)?.toDate();
      if (dataAgendamento == null) return false;

      // Busca dados do serviço
      final servicoId = appointmentData['servicoId'];
      DocumentSnapshot? servicoDoc;
      if (servicoId != null) {
        servicoDoc = await FirebaseFirestore.instance
            .collection('services')
            .doc(servicoId)
            .get();
      }

      final servicoNome = servicoDoc?.data() != null
          ? (servicoDoc!.data() as Map)['nome'] ?? 'Serviço'
          : 'Serviço';
      final duracaoMinutos = servicoDoc?.data() != null
          ? ((servicoDoc!.data() as Map)['duracao'] ?? 60)
          : 60;

      // Busca dados do cliente
      final clienteId = appointmentData['clientId'];
      DocumentSnapshot? clienteDoc;
      if (clienteId != null) {
        clienteDoc = await FirebaseFirestore.instance
            .collection('clients')
            .doc(clienteId)
            .get();
      }

      final clienteNome = clienteDoc?.data() != null
          ? (clienteDoc!.data() as Map)['nome'] ?? 'Cliente'
          : 'Cliente';

      final event = calendar.Event();
      event.summary = '$servicoNome - $clienteNome';
      event.description = '''
Agendamento MarkaAI
ID: $appointmentId
Status: ${appointmentData['status'] ?? 'confirmado'}
Valor: R\$ ${appointmentData['valor_total']?.toStringAsFixed(2) ?? '0.00'}
''';
      
      event.start = calendar.EventDateTime(
        dateTime: dataAgendamento,
        timeZone: 'America/Sao_Paulo',
      );
      
      event.end = calendar.EventDateTime(
        dateTime: dataAgendamento.add(Duration(minutes: duracaoMinutos)),
        timeZone: 'America/Sao_Paulo',
      );
      
      event.extendedProperties = calendar.EventExtendedProperties();
      event.extendedProperties!.private = {
        'markaai_appointment_id': appointmentId,
        'markaai_shop_id': appointmentData['shopId'] ?? '',
      };

      // Verifica se o evento já existe
      final existingEventId = appointmentData['googleCalendarEventId'];
      
      if (existingEventId != null) {
        // Atualiza evento existente
        await calendarApi.events.update(event, calendarId, existingEventId);
      } else {
        // Cria novo evento
        final created = await calendarApi.events.insert(event, calendarId);
        
        // Salva o ID do evento no Firestore
        await FirebaseFirestore.instance
            .collection('appointments')
            .doc(appointmentId)
            .update({'googleCalendarEventId': created.id});
      }

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao sincronizar evento: $e');
      return false;
    }
  }

  /// Remove um evento do Google Calendar
  static Future<bool> deleteAppointment({
    required String appointmentId,
    required String? eventId,
  }) async {
    if (eventId == null) return true; // Nada para deletar

    final calendarApi = await _getCalendarClient();
    if (calendarApi == null) return false;

    final calendarId = await _getOrCreateBackupCalendar();
    if (calendarId == null) return false;

    try {
      await calendarApi.events.delete(calendarId, eventId);
      
      // Remove referência no Firestore
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(appointmentId)
          .update({'googleCalendarEventId': FieldValue.delete()});
      
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao deletar evento: $e');
      return false;
    }
  }

  /// Sincroniza todos os agendamentos de uma loja (para donos)
  static Future<int> syncAllShopAppointments(String shopId) async {
    final appointments = await FirebaseFirestore.instance
        .collection('appointments')
        .where('shopId', isEqualTo: shopId)
        .where('status', whereIn: ['confirmado', 'aguardando_confirmacao'])
        .get();

    int synced = 0;
    for (var doc in appointments.docs) {
      final success = await syncAppointment(
        appointmentId: doc.id,
        appointmentData: doc.data(),
      );
      if (success) synced++;
    }

    return synced;
  }

  /// Sincroniza apenas os agendamentos de um funcionário específico
  static Future<int> syncEmployeeAppointments(String employeeId) async {
    final appointments = await FirebaseFirestore.instance
        .collection('appointments')
        .where('profissionalId', isEqualTo: employeeId)
        .where('status', whereIn: ['confirmado', 'aguardando_confirmacao'])
        .get();

    int synced = 0;
    for (var doc in appointments.docs) {
      final success = await syncAppointment(
        appointmentId: doc.id,
        appointmentData: doc.data(),
      );
      if (success) synced++;
    }

    return synced;
  }
}
