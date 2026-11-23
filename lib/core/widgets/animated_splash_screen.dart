import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:markaai/core/services/splash_config_service.dart';

/// Splash de abertura do MarkaAI em 3 etapas:
///
///  1. Somente o logo.
///  2. Ferramentas (tesoura, pente fino, escova, agenda, esmalte, pente garfo, lash) orbitam o logo e entram
///     nele em espiral; o logo "enche" e volta ao normal com mola. Depois entram o
///     slogan e uma frase curta (editavel no painel admin, por perfil).
///  3. Campanha de marketing enviada pelo admin. Sem campanha valida, so o logo.
///
/// O `AuthGate` chama [AnimatedSplashScreenState.playExitAnimation] quando a sessao
/// esta resolvida; a saida so ocorre depois da coreografia terminar.
class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({
    super.key,
    this.onComplete,
    this.progress = 0.0,
  });

  final VoidCallback? onComplete;

  /// Mantido por compatibilidade com o `AuthGate`; a coreografia nao depende dele.
  final double progress;

  @override
  State<AnimatedSplashScreen> createState() => AnimatedSplashScreenState();
}

class AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with TickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // Linha do tempo (ms) — dinâmica com 7 ferramentas essenciais
  // ---------------------------------------------------------------------------
  static const double _s2 = 800; // inicio da Etapa 2
  static const double _orbitIn = 450; // ferramentas surgem e orbitam
  static const double _spiralStart = 650; // 1a ferramenta espirala para dentro
  static const double _stagger = 150; // atraso entre ferramentas
  static const double _spiralDur = 900; // duracao de cada espiral
  static const double _s3 = 4500; // inicio da Etapa 3 (campanha)

  static const int _n = 7;
  static const double _rx = 100, _ry = 122, _omega = 1.9;
  static const double _baseWidth = 274; // largura de referencia do prototipo

  static const double _lastAbsorb = _spiralStart + (_n - 1) * _stagger + _spiralDur;
  static const double _release = _lastAbsorb + 120;

  static const List<String> _toolAssets = [
    'assets/images/splash_items/scissors_3d.png',
    'assets/images/splash_items/comb_3d.png',
    'assets/images/splash_items/hairbrush_3d.png',
    'assets/images/splash_items/agenda_3d.png',
    'assets/images/splash_items/nail_brush_3d.png',
    'assets/images/splash_items/afro_comb_3d.png',
    'assets/images/splash_items/lash_brush_3d.png',
  ];
  static const String _logoAsset = 'assets/images/logo_white_extend.png';

  static const Cubic _easeApple = Cubic(0.22, 1, 0.36, 1);

  // ---------------------------------------------------------------------------
  // Estado
  // ---------------------------------------------------------------------------
  late final Ticker _ticker;
  late final AnimationController _exitController;
  late final Animation<double> _exitOpacity;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final Completer<void> _sequenceDone = Completer<void>();
  Future<void>? _exitFuture;

  double _clock = 0;
  Duration _lastElapsed = Duration.zero;

  // Mola do logo (x = escala, v = velocidade)
  double _springX = 1;
  double _springV = 0;
  double _glow = 0;
  final List<bool> _absorbed = List<bool>.filled(_n, false);
  double _burstStart = -1;

  String? _phrase;

  // Campanha (Etapa 3)
  SplashCampaign? _preparedCampaign;
  ImageProvider? _preparedImage;
  SplashCampaign? _stage3Campaign;
  ImageProvider? _stage3Image;
  bool _stage3Latched = false;
  double _endMs = _s3;

  bool _assetsPrecached = false;

  @override
  void initState() {
    super.initState();

    // Remove a splash nativa assim que o primeiro frame Flutter e desenhado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });

    _exitController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _exitOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeOut),
    );

    SplashConfigService.instance.addListener(_prepareCampaign);

    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_assetsPrecached) {
      _assetsPrecached = true;
      // Decodifica antes para nao haver "pop-in" no meio da animacao.
      precacheImage(const AssetImage(_logoAsset), context);
      for (final asset in _toolAssets) {
        precacheImage(AssetImage(asset), context);
      }
      _prepareCampaign();
    }
  }

  @override
  void dispose() {
    SplashConfigService.instance.removeListener(_prepareCampaign);
    _ticker.dispose();
    _exitController.dispose();
    _frame.dispose();
    if (!_sequenceDone.isCompleted) _sequenceDone.complete();
    super.dispose();
  }

  /// Dispara a saida. So fade-out depois da coreografia (Etapas 1-3) terminar.
  Future<void> playExitAnimation() => _exitFuture ??= _runExit();

  Future<void> _runExit() async {
    await _sequenceDone.future;
    if (!mounted) return;
    await _exitController.forward();
    if (mounted) widget.onComplete?.call();
  }

  // ---------------------------------------------------------------------------
  // Campanha
  // ---------------------------------------------------------------------------

  Future<void> _prepareCampaign() async {
    if (_stage3Latched || !mounted) return;
    final service = SplashConfigService.instance;
    final campaign = service.readyCampaign;
    final image = service.campaignImage;
    if (campaign == null || image == null) {
      _preparedCampaign = null;
      _preparedImage = null;
      return;
    }
    try {
      await precacheImage(image, context);
    } catch (_) {
      return; // imagem ilegivel: Etapa 3 mostra so o logo
    }
    if (!mounted || _stage3Latched) return;
    _preparedCampaign = campaign;
    _preparedImage = image;
  }

  /// Decide, uma unica vez, o que a Etapa 3 mostra (evita mudar o tempo no meio).
  void _latchStage3() {
    _stage3Latched = true;
    _stage3Campaign = _preparedCampaign;
    _stage3Image = _preparedImage;
    final c = _stage3Campaign;
    // Se nao houver campanha cadastrada/ativa, a Etapa 3 nao existe: encerra direto em _s3.
    _endMs = c != null ? _s3 + c.display.inMilliseconds.toDouble() : _s3;
  }

  // ---------------------------------------------------------------------------
  // Curvas
  // ---------------------------------------------------------------------------
  static double _clamp01(double v) => v.clamp(0.0, 1.0).toDouble();
  static double _easeOutCubic(double p) => 1 - math.pow(1 - p, 3).toDouble();
  static double _easeInQuad(double p) => p * p;
  static double _easeInOutCubic(double p) =>
      p < 0.5 ? 4 * p * p * p : 1 - math.pow(-2 * p + 2, 3).toDouble() / 2;
  static double _smoothstep(double a, double b, double x) {
    final t = _clamp01((x - a) / (b - a));
    return t * t * (3 - 2 * t);
  }

  // ---------------------------------------------------------------------------
  // Passo da animacao
  // ---------------------------------------------------------------------------

  void _onTick(Duration elapsed) {
    final dt = math.min(48.0, (elapsed - _lastElapsed).inMicroseconds / 1000.0);
    _lastElapsed = elapsed;
    _advance(dt);
    _frame.value++;
  }

  void _advance(double dtMs) {
    _clock += dtMs;

    if (!_stage3Latched && _clock >= _s3) _latchStage3();
    if (_phrase == null && _clock >= _s2) {
      _phrase = SplashConfigService.instance.pickPhrase();
    }

    final inStage2 = _clock >= _s2 && _clock < _s3;
    final local = _clock - _s2;

    // Quanto do logo ja "encheu" (ferramentas absorvidas).
    var fill = 0.0;
    if (inStage2) {
      for (var i = 0; i < _n; i++) {
        final p = _clamp01((local - (_spiralStart + i * _stagger)) / _spiralDur);
        fill += _smoothstep(0.55, 1, p) / _n;
        if (p >= 0.9 && !_absorbed[i]) {
          _absorbed[i] = true;
          _springV += 0.24; // pequeno "gole" a cada ferramenta
        }
      }
    }

    var target = 1.0;
    if (inStage2) {
      if (local < _release) {
        target = 1 + 0.16 * fill;
      } else if (_burstStart < 0) {
        _burstStart = _clock;
      }
    }

    // Mola (sub-passos para estabilidade numerica)
    var rem = dtMs / 1000;
    while (rem > 0) {
      final h = math.min(rem, 1 / 120);
      final a = 210 * (target - _springX) - 17 * _springV;
      _springV += a * h;
      _springX += _springV * h;
      rem -= h;
    }

    _glow = inStage2
        ? (local < _release ? fill : math.max(0.0, 1 - (local - _release) / 600))
        : 0.0;

    if (_clock >= _endMs && !_sequenceDone.isCompleted) {
      _clock = _endMs;
      _sequenceDone.complete();
      _ticker.stop(); // fim: segura o ultimo quadro sem gastar bateria
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final unit = (mq.size.shortestSide / _baseWidth).clamp(0.9, 1.5).toDouble();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: const Color(0xFF1E0436),
        body: FadeTransition(
          opacity: _exitOpacity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // CSS "farthest-corner": raio ate o canto mais distante.
              final radius = 0.5 *
                  math.sqrt(constraints.maxWidth * constraints.maxWidth +
                      constraints.maxHeight * constraints.maxHeight) /
                  math.min(constraints.maxWidth, constraints.maxHeight);
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: radius,
                    colors: const [Color(0xFF4A1078), Color(0xFF310852), Color(0xFF1E0436)],
                    stops: const [0.0, 0.58, 1.0],
                  ),
                ),
                child: AnimatedBuilder(
                  animation: _frame,
                  builder: (context, _) => _buildScene(constraints, unit, mq.padding.bottom),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildScene(BoxConstraints box, double unit, double bottomInset) {
    final inStage2 = _clock >= _s2 && (_stage3Campaign != null ? _clock < _s3 : true);
    final local = _clock - _s2;
    final showText = local > _release + 150 && (_stage3Campaign == null || _clock < _s3);
    final logoWidth = 146 * unit;
    final textUnit = unit.clamp(1.0, 1.25).toDouble();

    return Stack(
      fit: StackFit.expand,
      children: [
        // Brilho suave no centro (cresce conforme o logo enche)
        if (_glow > 0.01)
          Center(
            child: Opacity(
              opacity: _glow.clamp(0.0, 1.0).toDouble(),
              child: Container(
                width: 256 * unit,
                height: 256 * unit,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x47D8B4FE), Color(0x004A1078)],
                    stops: [0.0, 0.68],
                  ),
                ),
              ),
            ),
          ),

        // Onda unica ao devolver o logo ao tamanho normal
        if (_burstStart >= 0) _buildBurst(unit),

        // Ferramentas (atras do logo => "entram" nele)
        if (inStage2) ..._buildTools(local, unit),

        // Brilho do proprio logo enquanto enche
        if (_glow > 0.02)
          Center(
            child: Transform.scale(
              scale: _springX,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 9 * unit, sigmaY: 9 * unit),
                child: Opacity(
                  opacity: (0.55 * _glow).clamp(0.0, 1.0).toDouble(),
                  child: Image.asset(_logoAsset, width: logoWidth, color: const Color(0xFFE9D5FF)),
                ),
              ),
            ),
          ),

        // Logo no centro EXATO da tela
        Center(
          child: Transform.scale(
            scale: _springX,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
              child: Image.asset(_logoAsset, width: logoWidth, semanticLabel: 'MarkaAI'),
            ),
          ),
        ),

        // Slogan logo abaixo do logo, sem deslocá-lo
        Positioned(
          left: 0,
          right: 0,
          top: box.maxHeight / 2 + 34 * unit,
          child: _fadeSlide(showText, _slogan(textUnit, unit)),
        ),

        // Frase curta + barra fina
        Positioned(
          left: 24,
          right: 24,
          bottom: 36 * unit + bottomInset,
          child: _fadeSlide(showText, _footer(textUnit, local)),
        ),

        // Etapa 3: campanha do admin
        if (_stage3Latched && _stage3Campaign != null && _stage3Image != null)
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOut,
              builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
              child: ColoredBox(
                color: _stage3Campaign!.background,
                child: Image(
                  image: _stage3Image!,
                  fit: _stage3Campaign!.fit,
                  width: double.infinity,
                  height: double.infinity,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fadeSlide(bool show, Widget child) {
    return AnimatedOpacity(
      opacity: show ? 1 : 0,
      duration: const Duration(milliseconds: 500),
      curve: _easeApple,
      child: AnimatedSlide(
        offset: show ? Offset.zero : const Offset(0, 0.35),
        duration: const Duration(milliseconds: 500),
        curve: _easeApple,
        child: child,
      ),
    );
  }

  Widget _slogan(double textUnit, double unit) {
    Widget line() => Container(width: 14 * unit, height: 1, color: Colors.white.withValues(alpha: 0.35));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        line(),
        SizedBox(width: 8 * unit),
        Text(
          'SIMPLES ASSIM',
          maxLines: 1,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 10 * textUnit,
            fontWeight: FontWeight.w500,
            letterSpacing: 10 * textUnit * 0.28,
            height: 1,
            decoration: TextDecoration.none,
          ),
        ),
        SizedBox(width: 8 * unit),
        line(),
      ],
    );
  }

  Widget _footer(double textUnit, double local) {
    final progress = _clamp01(local / (_s3 - _s2));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _phrase ?? '',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 12 * textUnit,
            letterSpacing: 12 * textUnit * 0.04,
            fontWeight: FontWeight.w400,
            decoration: TextDecoration.none,
          ),
        ),
        SizedBox(height: 12 * textUnit),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            width: 24 * textUnit,
            height: 1.5,
            child: Stack(
              children: [
                Container(color: Colors.white.withValues(alpha: 0.15)),
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(color: Colors.white.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBurst(double unit) {
    final t = _clamp01((_clock - _burstStart) / 900);
    if (t >= 1) return const SizedBox.shrink();
    final eased = const Cubic(0.16, 1, 0.3, 1).transform(t);
    final scale = 0.55 + (1.75 - 0.55) * eased;
    final opacity = 0.45 * (1 - t);
    return Center(
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: 170 * unit,
            height: 170 * unit,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTools(double local, double unit) {
    final qIn = _clamp01(local / _orbitIn);
    final widgets = <Widget>[];

    for (var i = 0; i < _n; i++) {
      final theta0 = i * (math.pi * 2 / _n) - math.pi / 2;
      final p = _clamp01((local - (_spiralStart + i * _stagger)) / _spiralDur);

      // Orbita continua + aceleracao angular ao espiralar (efeito redemoinho)
      final theta = theta0 + _omega * local / 1000 + 2.6 * _easeInQuad(p);
      // Raio: entra de fora (1.25 -> 1) e depois espirala suavemente ate 0
      final rIn = 1.25 - 0.25 * _easeOutCubic(qIn);
      final r = rIn * (1 - _easeInOutCubic(p));
      final dx = math.cos(theta) * _rx * r * unit;
      final dy = math.sin(theta) * _ry * r * unit;
      final scale = (0.6 + 0.4 * _easeOutCubic(qIn)) * (1 - 0.82 * _easeInQuad(p));

      final asset = _toolAssets[i];
      final isNailPolish = asset.contains('nail_brush');
      final isAgenda = asset.contains('agenda');

      final double rotDeg;
      if (isNailPolish) {
        // O vidro de esmalte inicia rigorosamente DE PÉ (0° vertical, tampa para cima)
        // e se mantém orientado para cima durante toda a órbita com apenas uma leve
        // inclinação dinâmica fluida (±10°), sem jamais ficar de cabeça para baixo.
        const baseCorrection = 3.1; // alinha os 3° de inclinação do frasco original
        final orbitTilt = math.sin(theta) * 10.0;
        final spiralTilt = -15.0 * _easeInQuad(p);
        rotDeg = baseCorrection + orbitTilt * _easeOutCubic(qIn) + spiralTilt;
      } else if (isAgenda) {
        // A agenda mantém sua perspectiva isométrica limpa e legível, iniciando
        // na pose natural e oscilando suavemente em curva.
        final orbitTilt = math.cos(theta) * 8.0;
        final spiralTilt = 18.0 * _easeInQuad(p);
        rotDeg = orbitTilt * _easeOutCubic(qIn) + spiralTilt;
      } else {
        // Ferramentas alongadas (tesoura, pentes, escova, lash)
        // seguem a dinâmica orbital de redemoinho.
        rotDeg = (theta * 180 / math.pi) * 0.35 + 170 * _easeInQuad(p);
      }

      final opacity =
          _easeOutCubic(qIn) * (1 - _smoothstep(0.62, 0.98, p)) * 0.95;

      if (opacity <= 0.01) continue;

      widgets.add(
        Center(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0).toDouble(),
            child: Transform.translate(
              offset: Offset(dx, dy),
              child: Transform.rotate(
                angle: rotDeg * math.pi / 180,
                child: Transform.scale(
                  scale: scale,
                  child: Image.asset(
                    asset,
                    width: 62 * unit,
                    height: 62 * unit,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}
