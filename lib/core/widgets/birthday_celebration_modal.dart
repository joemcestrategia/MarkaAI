import 'package:flutter/material.dart';
import 'dart:math' as math;

class BirthdayCelebrationModal extends StatefulWidget {
  final double discountPercent;
  final String shopName;
  final VoidCallback onAccept;

  const BirthdayCelebrationModal({
    super.key,
    required this.discountPercent,
    required this.shopName,
    required this.onAccept,
  });

  @override
  State<BirthdayCelebrationModal> createState() => _BirthdayCelebrationModalState();
}

class _BirthdayCelebrationModalState extends State<BirthdayCelebrationModal>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _loopController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  final List<_Particle> _particles = [];
  final List<_Balloon> _balloons = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..forward();

    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _scaleAnimation = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
    );

    // Create particles (confetti)
    for (int i = 0; i < 60; i++) {
      _particles.add(_Particle(_random));
    }

    // Create balloons
    for (int i = 0; i < 8; i++) {
      _balloons.add(_Balloon(_random));
    }

    _loopController.addListener(() {
      setState(() {
        for (var p in _particles) {
          p.update();
        }
        for (var b in _balloons) {
          b.update();
        }
      });
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _loopController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Background dismissible area
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              color: Colors.black.withOpacity(0.4),
            ),
          ),

          // Balloons
          ..._balloons.map((b) => Positioned(
                left: b.x * MediaQuery.of(context).size.width,
                top: b.y * MediaQuery.of(context).size.height,
                child: Opacity(
                  opacity: 0.7,
                  child: Icon(
                    Icons.circle,
                    size: b.size,
                    color: b.color,
                  ),
                ),
              )),

          // Modal Content
          Center(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  constraints: const BoxConstraints(maxWidth: 400),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cake, size: 80, color: Colors.white),
                      const SizedBox(height: 16),
                      const Text(
                        "FELIZ ANIVERSÁRIO!",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${widget.shopName} quer te presentear!",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              "${widget.discountPercent.toInt()}% OFF",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              "DESCONTO DE ANIVERSÁRIO",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "Válido para qualquer forma de pagamento.",
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                             Icon(Icons.info_outline, color: Colors.orange, size: 20),
                             SizedBox(width: 8),
                             Expanded(
                               child: Text(
                                "Lembre-se de apresentar seu documento com foto no dia do atendimento.",
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                             ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: widget.onAccept,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF2575FC),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            "ACEITAR PRESENTE",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Particles (Confetti)
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _ConfettiPainter(_particles),
            ),
          ),
        ],
      ),
    );
  }
}

class _Particle {
  late double x;
  late double y;
  late double vx;
  late double vy;
  late Color color;
  late double size;
  final math.Random random;

  _Particle(this.random) {
    x = random.nextDouble() * 400;
    y = random.nextDouble() * 800;
    vx = (random.nextDouble() - 0.5) * 2;
    vy = random.nextDouble() * 2 + 1;
    size = random.nextDouble() * 6 + 2;
    color = [
      Colors.red,
      Colors.blue,
      Colors.yellow,
      Colors.green,
      Colors.pink,
      Colors.purple,
      Colors.orange
    ][random.nextInt(7)];
  }

  void update() {
    x += vx;
    y += vy;
    if (y > 900) {
      y = -10;
      x = random.nextDouble() * 400;
    }
  }
}

class _Balloon {
  late double x;
  late double y;
  late double speed;
  late double size;
  late Color color;
  final math.Random random;

  _Balloon(this.random) {
    x = random.nextDouble();
    y = random.nextDouble() + 1.0;
    speed = random.nextDouble() * 0.002 + 0.001;
    size = random.nextDouble() * 40 + 30;
    color = [
      Colors.redAccent,
      Colors.blueAccent,
      Colors.yellowAccent,
      Colors.greenAccent,
      Colors.pinkAccent,
      Colors.purpleAccent,
      Colors.orangeAccent
    ][random.nextInt(7)].withOpacity(0.5);
  }

  void update() {
    y -= speed;
    if (y < -0.2) {
      y = 1.2;
      x = random.nextDouble();
    }
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  _ConfettiPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var p in particles) {
      paint.color = p.color;
      canvas.drawRect(
        Rect.fromLTWH(p.x * (size.width / 400), p.y * (size.height / 800), p.size, p.size),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
