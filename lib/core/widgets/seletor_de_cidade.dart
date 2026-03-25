import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../../core/utils/string_utils.dart';
import '../../core/theme/app_colors.dart';
import '../../core/data/cidades_brasil.dart';

const String _kCidadePrefsKey = 'app_cidade_selecionada';
const String _kCidadesListKey = 'app_cidades_salvas_v2';
const int _kMaxCidades = 4;

/// Model que representa a cidade selecionada pelo cliente, persistida localmente.
class CidadeSelecionada {
  final String cidade;
  final String estado;
  final DateTime definidoEm;
  final int? raioKm; // null = toda a cidade

  const CidadeSelecionada({
    required this.cidade,
    required this.estado,
    required this.definidoEm,
    this.raioKm,
  });

  Map<String, dynamic> toJson() => {
        'cidade': cidade,
        'estado': estado,
        'definidoEm': definidoEm.toIso8601String(),
        if (raioKm != null) 'raioKm': raioKm,
      };

  factory CidadeSelecionada.fromJson(Map<String, dynamic> json) {
    return CidadeSelecionada(
      cidade: json['cidade'] as String? ?? '',
      estado: json['estado'] as String? ?? '',
      definidoEm: DateTime.tryParse(json['definidoEm'] as String? ?? '') ??
          DateTime.now(),
      raioKm: json['raioKm'] as int?,
    );
  }

  CidadeSelecionada copyWith({int? raioKm, bool clearRaio = false}) {
    return CidadeSelecionada(
      cidade: cidade,
      estado: estado,
      definidoEm: definidoEm,
      raioKm: clearRaio ? null : (raioKm ?? this.raioKm),
    );
  }

  @override
  String toString() => '$cidade, $estado';
}

/// Serviço de persistência local da cidade selecionada.
class CidadePrefs {
  // â”€â”€ Cidade ativa (compatibilidade legada) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<CidadeSelecionada?> carregar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Tenta nova lista primeiro
      final list = await carregarLista();
      if (list.isNotEmpty) return list.first;
      // Fallback para chave legada
      final raw = prefs.getString(_kCidadePrefsKey);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CidadeSelecionada.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> salvar(CidadeSelecionada cidade) async {
    // Salva na lista e também mantém chave legada
    final list = await carregarLista();

    // Normalização para comparação (remove acentos e deixa em minúsculo)
    String normalize(String s) =>
        StringUtils.removeDiacritics(s).toLowerCase().trim();
    final normCidade = normalize(cidade.cidade);
    final normEstado = normalize(cidade.estado);

    // Remove se já existia uma entrada similar (evita "São Paulo" vs "Sao Paulo")
    list.removeWhere((c) =>
        normalize(c.cidade) == normCidade && normalize(c.estado) == normEstado);

    // Adiciona no início
    list.insert(0, cidade);
    if (list.length > _kMaxCidades) list.removeLast();
    await salvarLista(list);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCidadePrefsKey, jsonEncode(cidade.toJson()));
  }

  static Future<void> limpar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCidadePrefsKey);
    await prefs.remove(_kCidadesListKey);
  }

  // â”€â”€ Lista de cidades salvas â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<List<CidadeSelecionada>> carregarLista() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCidadesListKey);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) =>
              CidadeSelecionada.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> salvarLista(List<CidadeSelecionada> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kCidadesListKey, jsonEncode(list.map((c) => c.toJson()).toList()));
  }

  static Future<void> removerDaLista(CidadeSelecionada cidade) async {
    final list = await carregarLista();
    list.removeWhere(
        (c) => c.cidade == cidade.cidade && c.estado == cidade.estado);
    await salvarLista(list);
  }
}

/// Botão compacto exibido no header do ClientHomePage mostrando a cidade atual.
/// Ao tocar, abre o [SeletorDeCidadeModal].
class SeletorDeCidadeButton extends StatelessWidget {
  final CidadeSelecionada? cidadeSelecionada;
  final VoidCallback onTap;

  const SeletorDeCidadeButton({
    super.key,
    required this.cidadeSelecionada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasCity = cidadeSelecionada != null;
    final cityLabel = hasCity ? cidadeSelecionada!.cidade : 'Escolher cidade';
    final raioLabel = (hasCity && cidadeSelecionada!.raioKm != null)
        ? ' Â· ${cidadeSelecionada!.raioKm}km'
        : '';
    final label = '$cityLabel$raioLabel';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on,
              size: 16,
              color: hasCity ? AppColors.primaryPurple : Colors.grey[500],
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: hasCity ? Colors.black87 : Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: hasCity ? Colors.grey[400] : Colors.grey[500],
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal exibido quando o usuário quer selecionar ou trocar de cidade.
/// Busca cidades disponíveis diretamente no Firestore (lojas com cidade cadastrada),
/// suporta autocomplete com debounce, seleção de raio e múltiplas cidades salvas.
class SeletorDeCidadeModal extends StatefulWidget {
  final void Function(CidadeSelecionada cidade) onCidadeSelecionada;
  final CidadeSelecionada? cidadeAtual;

  const SeletorDeCidadeModal({
    super.key,
    required this.onCidadeSelecionada,
    this.cidadeAtual,
  });

  static Future<List<CidadeOpcao>> getCitySuggestions(String query) async {
    if (query.isEmpty) return [];
    final q = StringUtils.removeDiacritics(query).toLowerCase().trim();
    final matches = kMunicipiosBrasil
        .where((e) => StringUtils.removeDiacritics(e.$1).toLowerCase().contains(q))
        .map((e) => CidadeOpcao(cidade: e.$1, estado: e.$2, count: 0))
        .toList();
        
    matches.sort((a, b) {
      final aNome = StringUtils.removeDiacritics(a.cidade).toLowerCase();
      final bNome = StringUtils.removeDiacritics(b.cidade).toLowerCase();
      final aStarts = aNome.startsWith(q) ? 0 : 1;
      final bStarts = bNome.startsWith(q) ? 0 : 1;
      if (aStarts != bStarts) return aStarts.compareTo(bStarts);
      return a.cidade.compareTo(b.cidade);
    });
    
    return matches.take(15).toList();
  }



  @override
  State<SeletorDeCidadeModal> createState() => _SeletorDeCidadeModalState();
}

class _SeletorDeCidadeModalState extends State<SeletorDeCidadeModal> {
  List<CidadeSelecionada> _cidadesSalvas = [];
  final bool _loading = false;
  bool _gpsLoading = false;

  // Etapa: null = busca, cidade selecionada = escolher raio
  CidadeOpcao? _cidadeEscolhida;
  int? _raioSelecionado;

  @override
  void initState() {
    super.initState();
    _loadCidadesSalvas();
    if (widget.cidadeAtual != null) {
      _raioSelecionado = widget.cidadeAtual!.raioKm;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadCidadesSalvas() async {
    final list = await CidadePrefs.carregarLista();
    if (mounted) setState(() => _cidadesSalvas = list);
  }

  void _selecionarCidade(CidadeOpcao opcao) {
    setState(() {
      _cidadeEscolhida = opcao;
      _raioSelecionado = null;
    });
  }

  void _confirmar() async {
    if (_cidadeEscolhida == null) return;
    final cs = CidadeSelecionada(
      cidade: _cidadeEscolhida!.cidade,
      estado: _cidadeEscolhida!.estado,
      definidoEm: DateTime.now(),
      raioKm: _raioSelecionado,
    );
    await CidadePrefs.salvar(cs);
    if (mounted) {
      Navigator.pop(context);
      widget.onCidadeSelecionada(cs);
    }
  }

  void _selecionarCidadeSalva(CidadeSelecionada cs) async {
    await CidadePrefs.salvar(cs);
    if (mounted) {
      Navigator.pop(context);
      widget.onCidadeSelecionada(cs);
    }
  }

  void _removerCidadeSalva(CidadeSelecionada cs) async {
    await CidadePrefs.removerDaLista(cs);
    _loadCidadesSalvas();
  }

  Future<void> _usarLocalizacaoGPS() async {
    setState(() => _gpsLoading = true);
    try {
      // 1. Verifica permissão
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Permissão de localização negada. Permita nas configurações.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 2. Obtém posição GPS
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // 3. Reverse geocode para obter cidade e estado
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
        localeIdentifier: 'pt_BR',
      );

      if (placemarks.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Não foi possível identificar sua cidade.'),
                backgroundColor: Colors.orange),
          );
        }
        return;
      }

      final place = placemarks.first;
      final cidade = (place.subAdministrativeArea ??
              place.locality ??
              place.administrativeArea ??
              '')
          .trim();
      final estado = (place.administrativeArea ?? '').trim();

      if (cidade.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Cidade não identificada pela localização.'),
                backgroundColor: Colors.orange),
          );
        }
        return;
      }

      // 4. Salva e confirma automaticamente
      final cs = CidadeSelecionada(
        cidade: cidade,
        estado: estado,
        definidoEm: DateTime.now(),
      );
      await CidadePrefs.salvar(cs);

      if (mounted) {
        Navigator.pop(context);
        widget.onCidadeSelecionada(cs);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao obter localização: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
            child: Row(
              children: [
                if (_cidadeEscolhida != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() => _cidadeEscolhida = null),
                    color: AppColors.primaryPurple,
                  )
                else
                  const Icon(Icons.location_city,
                      color: AppColors.primaryPurple),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _cidadeEscolhida != null
                        ? _cidadeEscolhida!.cidade
                        : 'Em qual cidade você está?',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          if (_cidadeEscolhida == null) ...[
            // â”€â”€ Campo de busca â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TypeAheadField<CidadeOpcao>(
                builder: (context, controller, focusNode) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: false,
                    decoration: InputDecoration(
                      hintText: 'Buscar cidade...',
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.primaryPurple),
                      suffixIcon: _loading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryPurple),
                              ),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  );
                },
                suggestionsCallback: (pattern) async {
                  return await SeletorDeCidadeModal.getCitySuggestions(pattern);
                },
                itemBuilder: (context, suggestion) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_city,
                        size: 18, color: Colors.grey),
                    title: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            color: Colors.black87, fontSize: 14),
                        children: [
                          TextSpan(
                            text: suggestion.cidade,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text: ' — ${suggestion.estado}',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                onSelected: (suggestion) {
                  _selecionarCidade(suggestion);
                },
                loadingBuilder: (context) => const Padding(
                  padding: EdgeInsets.all(16.0),
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                emptyBuilder: (context) => const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Nenhuma cidade encontrada'),
                ),
                debounceDuration: const Duration(milliseconds: 300),
              ),
            ),

            // â”€â”€ Botão GPS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _gpsLoading ? null : _usarLocalizacaoGPS,
                  icon: _gpsLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primaryPurple),
                        )
                      : const Icon(Icons.my_location,
                          size: 16, color: AppColors.primaryPurple),
                  label: Text(
                    _gpsLoading
                        ? 'Obtendo localização...'
                        : 'Usar minha localização',
                    style: const TextStyle(
                        color: AppColors.primaryPurple,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: AppColors.primaryPurple.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    backgroundColor:
                        AppColors.primaryPurple.withValues(alpha: 0.04),
                  ),
                ),
              ),
            ),

            // â”€â”€ Cidades salvas (chips) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            if (_cidadesSalvas.isNotEmpty) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('Minhas cidades',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                        letterSpacing: 0.5)),
              ),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _cidadesSalvas.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final cs = _cidadesSalvas[i];
                    final isActive = widget.cidadeAtual?.cidade == cs.cidade &&
                        widget.cidadeAtual?.estado == cs.estado;
                    return GestureDetector(
                      onLongPress: () => _removerCidadeSalva(cs),
                      child: ActionChip(
                        avatar: Icon(
                          Icons.location_on,
                          size: 14,
                          color:
                              isActive ? Colors.white : AppColors.primaryPurple,
                        ),
                        label: Text(
                          cs.raioKm != null
                              ? '${cs.cidade} Â· ${cs.raioKm}km'
                              : cs.cidade,
                          style: TextStyle(
                            fontSize: 12,
                            color: isActive
                                ? Colors.white
                                : AppColors.primaryPurple,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        backgroundColor: isActive
                            ? AppColors.primaryPurple
                            : AppColors.primaryPurple.withValues(alpha: 0.08),
                        side: BorderSide(
                            color:
                                AppColors.primaryPurple.withValues(alpha: 0.3)),
                        onPressed: () => _selecionarCidadeSalva(cs),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 0),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text('Pressione e segure para remover',
                    style: TextStyle(fontSize: 10, color: Colors.grey[400])),
              ),
            ],
          ] else ...[
            // â”€â”€ Seleção de Raio â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'Qual o raio de busca em ${_cidadeEscolhida!.cidade}?',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final raio in [5, 10, 20, 50])
                    _RaioChip(
                      label: '$raio km',
                      selected: _raioSelecionado == raio,
                      onTap: () => setState(() => _raioSelecionado = raio),
                    ),
                  _RaioChip(
                    label: 'Toda a cidade',
                    selected: _raioSelecionado == null,
                    onTap: () => setState(() => _raioSelecionado = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _confirmar,
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: Text(
                    _raioSelecionado != null
                        ? 'Buscar em ${_cidadeEscolhida!.cidade} Â· ${_raioSelecionado}km'
                        : 'Buscar em toda ${_cidadeEscolhida!.cidade}',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tela cheia para seleção de cidade — use Navigator.push para navegar a ela.
/// Equivalente ao [SeletorDeCidadeModal] mas ocupa a tela inteira.
class SeletorDeCidadePage extends StatefulWidget {
  final void Function(CidadeSelecionada cidade) onCidadeSelecionada;
  final CidadeSelecionada? cidadeAtual;

  const SeletorDeCidadePage({
    super.key,
    required this.onCidadeSelecionada,
    this.cidadeAtual,
  });

  @override
  State<SeletorDeCidadePage> createState() => _SeletorDeCidadePageState();
}

class _SeletorDeCidadePageState extends State<SeletorDeCidadePage> {
  final _searchCtrl = TextEditingController();
  List<CidadeOpcao> _sugestoes = [];
  List<CidadeSelecionada> _cidadesSalvas = [];
  bool _loading = false;
  bool _firstLoad = true;
  bool _gpsLoading = false;
  Timer? _debounce;
  CidadeOpcao? _cidadeEscolhida;
  int? _raioSelecionado;

  /// Mapa cidade_lowercase -> contagem de lojas cadastradas (carregado uma vez)
  Map<String, int> _shopCountByCity = {};

  @override
  void initState() {
    super.initState();
    _loadCidadesSalvas();
    _loadShopCities(); // carrega lojas cadastradas do Firestore
    _searchCtrl.addListener(_onSearchChanged);
    if (widget.cidadeAtual != null) {
      _raioSelecionado = widget.cidadeAtual!.raioKm;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCidadesSalvas() async {
    final list = await CidadePrefs.carregarLista();
    if (mounted) setState(() => _cidadesSalvas = list);
  }

  /// Carrega uma vez do Firestore quais cidades têm lojas e quantas
  Future<void> _loadShopCities() async {
    try {
      final snap = await Supabase.instance.client
          .from('shops')
          .select('city, state');
      final Map<String, int> counts = {};
      for (final item in snap) {
        final cidade = (item['city'] ?? item['cidade'] ?? '').toString().trim().toLowerCase();
        if (cidade.isNotEmpty) {
          counts[cidade] = (counts[cidade] ?? 0) + 1;
        }
      }
      if (mounted) {
        setState(() {
          _shopCountByCity = counts;
        });
        // Mostra cidades populares ao abrir (sem query)
        if (_searchCtrl.text.trim().isEmpty) {
          _buscarCidades('');
        }
      }
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _buscarCidades(_searchCtrl.text.trim());
    });
  }

  /// Busca cidades via lista estática de municípios embutida no app
  void _buscarCidades(String query) {
    if (query.isEmpty) {
      // Sem query: mostra cidades com lojas cadastradas, ordenadas por popularidade
      final comLojas = _shopCountByCity.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (mounted) {
        setState(() {
          _sugestoes = comLojas
              .map((e) => CidadeOpcao(
                  cidade: _capitalize(e.key), estado: '', count: e.value))
              .toList();
          _firstLoad = false;
          _loading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _loading = true);
    
    final q = StringUtils.removeDiacritics(query).toLowerCase().trim();
    final matches = kMunicipiosBrasil
        .where((e) => StringUtils.removeDiacritics(e.$1).toLowerCase().contains(q))
        .map((e) {
          final count = _shopCountByCity[e.$1.toLowerCase()] ?? 0;
          return CidadeOpcao(cidade: e.$1, estado: e.$2, count: count);
        }).toList();

    // Ordenação inteligente: shops count e depois prefixo
    matches.sort((a, b) {
      if (b.count != a.count) return b.count.compareTo(a.count);
      final aNome = StringUtils.removeDiacritics(a.cidade).toLowerCase();
      final bNome = StringUtils.removeDiacritics(b.cidade).toLowerCase();
      final aStarts = aNome.startsWith(q) ? 0 : 1;
      final bStarts = bNome.startsWith(q) ? 0 : 1;
      if (aStarts != bStarts) return aStarts.compareTo(bStarts);
      return a.cidade.compareTo(b.cidade);
    });

    if (mounted) {
      setState(() {
        _sugestoes = matches.take(60).toList();
        _loading = false;
        _firstLoad = false;
      });
    }
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((w) {
      if (w.length <= 2) return w.toUpperCase();
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
  }



  void _selecionarCidade(CidadeOpcao opcao) {
    setState(() {
      _cidadeEscolhida = opcao;
      _raioSelecionado = null;
    });
  }

  void _confirmar() async {
    if (_cidadeEscolhida == null) return;
    final cs = CidadeSelecionada(
      cidade: _cidadeEscolhida!.cidade,
      estado: _cidadeEscolhida!.estado,
      definidoEm: DateTime.now(),
      raioKm: _raioSelecionado,
    );
    await CidadePrefs.salvar(cs);
    if (mounted) {
      Navigator.pop(context);
      widget.onCidadeSelecionada(cs);
    }
  }

  void _selecionarCidadeSalva(CidadeSelecionada cs) async {
    await CidadePrefs.salvar(cs);
    if (mounted) {
      Navigator.pop(context);
      widget.onCidadeSelecionada(cs);
    }
  }

  void _removerCidadeSalva(CidadeSelecionada cs) async {
    await CidadePrefs.removerDaLista(cs);
    _loadCidadesSalvas();
  }

  Future<void> _usarLocalizacaoGPS() async {
    setState(() => _gpsLoading = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Permissão de localização negada.'),
              backgroundColor: Colors.red));
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      final placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude,
          localeIdentifier: 'pt_BR');
      if (placemarks.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Não foi possível identificar sua cidade.'),
              backgroundColor: Colors.orange));
        }
        return;
      }
      final place = placemarks.first;
      final cidade = (place.subAdministrativeArea ??
              place.locality ??
              place.administrativeArea ??
              '')
          .trim();
      final estado = (place.administrativeArea ?? '').trim();
      if (cidade.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Cidade não identificada.'),
              backgroundColor: Colors.orange));
        }
        return;
      }
      final cs = CidadeSelecionada(
          cidade: cidade, estado: estado, definidoEm: DateTime.now());
      await CidadePrefs.salvar(cs);
      if (mounted) {
        Navigator.pop(context);
        widget.onCidadeSelecionada(cs);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro ao obter localização: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _cidadeEscolhida != null
              ? _cidadeEscolhida!.cidade
              : 'Onde você está?',
          style: const TextStyle(
              color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey[100]),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_cidadeEscolhida == null) ...[
            // Campo de busca
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Buscar cidade...',
                  prefixIcon:
                      const Icon(Icons.search, color: AppColors.primaryPurple),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primaryPurple)))
                      : null,
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            // Botão GPS
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _gpsLoading ? null : _usarLocalizacaoGPS,
                  icon: _gpsLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primaryPurple))
                      : const Icon(Icons.my_location,
                          size: 16, color: AppColors.primaryPurple),
                  label: Text(
                    _gpsLoading
                        ? 'Obtendo localização...'
                        : 'Usar minha localização',
                    style: const TextStyle(
                        color: AppColors.primaryPurple,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: AppColors.primaryPurple.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    backgroundColor:
                        AppColors.primaryPurple.withValues(alpha: 0.04),
                  ),
                ),
              ),
            ),
            // Cidades salvas
            if (_cidadesSalvas.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text('Minhas cidades',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                        letterSpacing: 0.5)),
              ),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _cidadesSalvas.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final cs = _cidadesSalvas[i];
                    final isActive = widget.cidadeAtual?.cidade == cs.cidade &&
                        widget.cidadeAtual?.estado == cs.estado;
                    return GestureDetector(
                      onLongPress: () => _removerCidadeSalva(cs),
                      child: ActionChip(
                        avatar: Icon(Icons.location_on,
                            size: 14,
                            color: isActive
                                ? Colors.white
                                : AppColors.primaryPurple),
                        label: Text(
                          cs.raioKm != null
                              ? '${cs.cidade} Â· ${cs.raioKm}km'
                              : cs.cidade,
                          style: TextStyle(
                              fontSize: 12,
                              color: isActive
                                  ? Colors.white
                                  : AppColors.primaryPurple,
                              fontWeight: FontWeight.w600),
                        ),
                        backgroundColor: isActive
                            ? AppColors.primaryPurple
                            : AppColors.primaryPurple.withValues(alpha: 0.08),
                        side: BorderSide(
                            color:
                                AppColors.primaryPurple.withValues(alpha: 0.3)),
                        onPressed: () => _selecionarCidadeSalva(cs),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 0),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 2),
                child: Text('Pressione e segure para remover',
                    style: TextStyle(fontSize: 10, color: Colors.grey[400])),
              ),
            ],
            const Divider(height: 16),
            // Lista de sugestões — Expanded para preencher o restante da tela
            Expanded(
              child: _firstLoad
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primaryPurple))
                  : _sugestoes.isEmpty
                      ? Center(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                              Icon(Icons.location_off,
                                  size: 48, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text('Nenhuma cidade encontrada.',
                                  style: TextStyle(color: Colors.grey[500])),
                            ]))
                      : ListView.builder(
                          itemCount: _sugestoes.length,
                          itemBuilder: (context, i) {
                            final c = _sugestoes[i];
                            final isSelected =
                                widget.cidadeAtual?.cidade == c.cidade &&
                                    widget.cidadeAtual?.estado == c.estado;
                            return ListTile(
                              leading: Icon(Icons.location_on,
                                  size: 20,
                                  color: isSelected
                                      ? AppColors.primaryPurple
                                      : Colors.grey[400]),
                              title: Text(c.cidade,
                                  style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? AppColors.primaryPurple
                                          : Colors.black87)),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(c.estado,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[500])),
                                    if (c.count > 0) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: AppColors.primaryPurple
                                                .withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Text('${c.count}',
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: AppColors.primaryPurple,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ]),
                              onTap: () => _selecionarCidade(c),
                            );
                          },
                        ),
            ),
          ] else ...[
            // Seleção de Raio
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Text(
                  'Qual o raio de busca em ${_cidadeEscolhida!.cidade}?',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final raio in [5, 10, 20, 50])
                    _RaioChip(
                        label: '$raio km',
                        selected: _raioSelecionado == raio,
                        onTap: () => setState(() => _raioSelecionado = raio)),
                  _RaioChip(
                      label: 'Toda a cidade',
                      selected: _raioSelecionado == null,
                      onTap: () => setState(() => _raioSelecionado = null)),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _confirmar,
                  icon: const Icon(Icons.check_circle, size: 20),
                  label: Text(
                      _raioSelecionado != null
                          ? 'Buscar em ${_cidadeEscolhida!.cidade} Â· ${_raioSelecionado}km'
                          : 'Buscar em toda ${_cidadeEscolhida!.cidade}',
                      style: const TextStyle(fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CidadeOpcao {
  final String cidade;
  final String estado;
  final int count;
  const CidadeOpcao(
      {required this.cidade, required this.estado, required this.count});
}

class _RaioChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RaioChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryPurple : Colors.grey[100],
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? AppColors.primaryPurple : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
