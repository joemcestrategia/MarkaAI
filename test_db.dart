import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient('https://uhccgcojwqvkfyzrmebv.supabase.co', 'sb_publishable_gmX2ol9O_y3XjHt8bJ-NgQ_b2nfxFmR');
  
  try {
    final res = await client.from('shops').select('id, nome, cidade, city, ativo, endereco').or('cidade.ilike.%itabirito%,city.ilike.%itabirito%');
    print("TOTAL LOJAS ENCONTRADAS EM ITABIRITO: \${res.length}");
    for (var r in res) {
      print("LOJA: \${r['nome']} | ATIVA: \${r['ativo']} | CIDADE: \${r['cidade']} | CITY: \${r['city']}");
    }
  } catch (e) {
    print("Error: \$e");
  }
}
