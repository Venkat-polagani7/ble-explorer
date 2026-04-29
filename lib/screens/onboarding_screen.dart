
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/permission_service.dart';

// ══════════════════════════════════════════════════════════════
// ONBOARDING SCREEN
// • Checks if permissions are already granted → skip to home
// • Otherwise shows animated intro + bottom-sheet permission flow
// • Play Store compliant: user can skip/deny without being blocked
// ══════════════════════════════════════════════════════════════

class OnboardingScreen extends StatefulWidget {
  /// Called only when this widget is used as a route target;
  /// navigation to HomeScreen is handled internally.
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;

  bool _checking = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));

    _initCheck();
  }

  /// If all permissions already granted, go straight to home.
  Future<void> _initCheck() async {
    final granted = await PermissionService.areAllAlreadyGranted();
    if (!mounted) return;
    if (granted) {
      _goHome();
      return;
    }
    setState(() => _checking = false);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _fadeCtrl.forward();
        _slideCtrl.forward();
      }
    });
  }

  void _goHome() {
    if (!mounted) return;
    // Notify root widget to switch to HomeScreen via setState.
    // This is safer than Navigator.pushReplacement from within onboarding
    // because it avoids potential "context not in tree" issues.
    widget.onComplete();
  }

  void _onGetStarted() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false, // user must tap allow or skip
      builder: (_) => _PermissionSheet(onAllDone: _goHome),
    );
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E1A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0E1A),
              Color(0xFF0D1B2A),
              Color(0xFF0A1628),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),
                    _TopBadge(),
                    const SizedBox(height: 8),
                    Expanded(flex: 5, child: _LottieSection()),
                    const _FeaturePills(),
                    const SizedBox(height: 32),
                    const Text(
                      'Connect. Inspect.\nDiagnose.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.18,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Professional BLE toolkit for\nscanning, diagnostics and real-time logs.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF8EACC8),
                        height: 1.6,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 36),
                    _GetStartedButton(onTap: _onGetStarted),
                    const SizedBox(height: 16),
                    const Text(
                      'No account required · Works offline',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF4A6580),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────

class _TopBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E3A5F)),
        color: const Color(0xFF0D1E35),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF00D4AA),
            ),
          ),
          const SizedBox(width: 7),
          const Text(
            'BLE Explorer',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF00D4AA),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _LottieSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF00D4AA).withValues(alpha: 0.08),
                const Color(0xFF0066CC).withValues(alpha: 0.04),
                Colors.transparent,
              ],
            ),
          ),
        ),
        Lottie.asset(
          'assets/lottie/ble_scan.json',
          width: 220,
          height: 220,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const _FallbackAnimation(),
        ),
      ],
    );
  }
}

class _FallbackAnimation extends StatefulWidget {
  const _FallbackAnimation();

  @override
  State<_FallbackAnimation> createState() => _FallbackAnimationState();
}

class _FallbackAnimationState extends State<_FallbackAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          for (final scale in [1.0, 0.7, 0.45])
            Opacity(
              opacity:
                  (0.12 + 0.08 * (1 - scale)) * _pulse.value + 0.04,
              child: Container(
                width: 200 * scale,
                height: 200 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF00D4AA),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          const Icon(
            Icons.bluetooth_searching_rounded,
            size: 52,
            color: Color(0xFF00D4AA),
          ),
        ],
      ),
    );
  }
}

class _FeaturePills extends StatelessWidget {
  const _FeaturePills();

  static const _features = [
    (Icons.radar_rounded, 'Scan'),
    (Icons.manage_search_rounded, 'Inspect'),
    (Icons.monitor_heart_outlined, 'Diagnose'),
    (Icons.receipt_long_rounded, 'Logs'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _features.map((f) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: const Color(0xFF0D1E35),
            border: Border.all(color: const Color(0xFF1A3050)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(f.$1, size: 14, color: const Color(0xFF00AAFF)),
              const SizedBox(width: 5),
              Text(
                f.$2,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFB0C8E0),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _GetStartedButton extends StatefulWidget {
  final VoidCallback onTap;

  const _GetStartedButton({required this.onTap});

  @override
  State<_GetStartedButton> createState() => _GetStartedButtonState();
}

class _GetStartedButtonState extends State<_GetStartedButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.96).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF0066CC), Color(0xFF00AAFF)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0066CC).withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Get Started',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded,
                  color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Permission Bottom Sheet ───────────────────────────────────

class _PermissionSheet extends StatefulWidget {
  final VoidCallback onAllDone;

  const _PermissionSheet({required this.onAllDone});

  @override
  State<_PermissionSheet> createState() => _PermissionSheetState();
}

class _PermissionSheetState extends State<_PermissionSheet> {
  int _step = 0;
  bool _requesting = false;

  List<Permission> get _permissions =>
      PermissionService.orderedOnboardingPermissions;

  bool get _isLast => _step == _permissions.length - 1;

  Future<void> _requestCurrent() async {
    if (_requesting || _permissions.isEmpty) {
      _finish();
      return;
    }
    setState(() => _requesting = true);

    try {
      final perm = _permissions[_step];
      final status = await perm.request();

      // If permanently denied, open app settings
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
    } catch (_) {
      // Silently handle — never block the user
    }

    if (!mounted) return;
    setState(() => _requesting = false);

    if (_isLast) {
      _finish();
    } else {
      setState(() => _step++);
    }
  }

  void _finish() {
    Navigator.of(context).pop();
    widget.onAllDone();
  }

  void _skip() {
    if (_isLast) {
      _finish();
    } else {
      setState(() => _step++);
    }
  }

  @override
  Widget build(BuildContext context) {
    // If no permissions needed (iOS or already granted edge case)
    if (_permissions.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
      return const SizedBox.shrink();
    }

    final perm = _permissions[_step];
    final title = PermissionService.labelFor(perm);
    final desc = PermissionService.descriptionFor(perm);
    final color = _step == 0
        ? const Color(0xFF00AAFF)
        : const Color(0xFF00D4AA);
    final icon = _step == 0
        ? Icons.bluetooth_rounded
        : Icons.bluetooth_connected_rounded;

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1A3050)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A5F),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 28),

            // Step dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_permissions.length, (i) {
                final active = i == _step;
                final done = i < _step;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: done
                        ? const Color(0xFF00D4AA)
                        : active
                            ? const Color(0xFF00AAFF)
                            : const Color(0xFF1E3A5F),
                  ),
                );
              }),
            ),
            const SizedBox(height: 28),

            // Icon circle
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Container(
                key: ValueKey(_step),
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.12),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: color, size: 34),
              ),
            ),
            const SizedBox(height: 20),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Column(
                key: ValueKey(_step),
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    desc,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6A8FAF),
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Allow button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0055BB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: _requesting ? null : _requestCurrent,
                child: _requesting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isLast ? 'Allow & Continue' : 'Allow',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),

            // Skip — Play Store requires this option
            TextButton(
              onPressed: _requesting ? null : _skip,
              child: Text(
                _isLast ? 'Skip for now' : 'Not now',
                style: const TextStyle(
                  color: Color(0xFF4A6580),
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 4),

            const Text(
              'Permissions are used only for device connectivity.\nNo data leaves your device.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF2E4A63),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
