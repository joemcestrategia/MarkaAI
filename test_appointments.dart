import 'dart:convert';
import 'package:supabase/supabase.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://uhccgcojwqvkfyzrmebv.supabase.co',
    'sb_publishable_gmX2ol9O_y3XjHt8bJ-NgQ_b2nfxFmR',
  );

  print('Buscando TODOS os agendamentos de marco/2026...');
  final marchAppts = await supabase
      .from('appointments')
      .select()
      .gte('scheduled_at', '2026-03-01T00:00:00+00:00')
      .order('scheduled_at', ascending: false);

  for (var a in marchAppts) {
    print('ID: ${a['id']} | DATA: ${a['scheduled_at']}');
    print('CLIENT: ${a['client_name']} | SERV: ${a['service_name']}');
    print('RAW: ${jsonEncode(a)}');
    print('---');
  }
}
