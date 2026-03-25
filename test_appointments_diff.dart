import 'dart:convert';
import 'package:supabase/supabase.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://uhccgcojwqvkfyzrmebv.supabase.co',
    'sb_publishable_gmX2ol9O_y3XjHt8bJ-NgQ_b2nfxFmR',
  );

  print('Buscando as diferencas entre COM NOME e SEM NOME em marco...');
  final marchAppts = await supabase
      .from('appointments')
      .select()
      .gte('scheduled_at', '2026-03-01T00:00:00+00:00')
      .order('scheduled_at', ascending: false);

  Map<String, dynamic>? hasName;
  Map<String, dynamic>? noName;

  for (var a in marchAppts) {
    if (a['client_name'] != null && a['client_name'].toString().isNotEmpty && hasName == null) {
      hasName = a;
    }
    if (a['client_name'] == null && noName == null) {
      noName = a;
    }
  }

  print('\r\n---- AGENDAMENTO NOVO CRIADO RECENTEMENTE (QUE FUNCIONA) ----');
  print(jsonEncode(hasName));

  print('\r\n---- AGENDAMENTO ANTIGO (QUE EXIBE SÓ PREÇO) ----');
  print(jsonEncode(noName));
}
