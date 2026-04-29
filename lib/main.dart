import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'services/permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait for consistent BLE tool UX
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0E1A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // ONLY check if permissions are already granted — never request here.
  // Requesting before runApp() means no Android Activity context exists yet,
  // so dialogs would never show and all requests silently return denied.
  final permissionsGranted = await PermissionService.areAllAlreadyGranted();

  runApp(BleExplorerRoot(skipOnboarding: permissionsGranted));
}

class BleExplorerRoot extends StatefulWidget {
  final bool skipOnboarding;

  const BleExplorerRoot({super.key, required this.skipOnboarding});

  @override
  State<BleExplorerRoot> createState() => _BleExplorerRootState();
}

class _BleExplorerRootState extends State<BleExplorerRoot> {
  late bool _skipOnboarding;

  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _skipOnboarding = widget.skipOnboarding;
  }

  void _onSplashComplete() {
    if (mounted) {
      setState(() => _showSplash = false);
    }
  }

  void _onOnboardingComplete() {
    if (mounted) {
      setState(() {
        _showSplash = false;
        _skipOnboarding = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Explorer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF8B5CF6),
          surface: Color(0xFF111827),
          error: Color(0xFFEF4444),
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      // AnimatedSwitcher: Splash → Onboarding → Home (smooth cross-fades)
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 800),
        child: _showSplash
            ? SplashScreen(
                key: const ValueKey('splash'),
                skipOnboarding: _skipOnboarding,
                onComplete: _onSplashComplete,
              )
            : (_skipOnboarding
                ? const HomeScreen(key: ValueKey('home'))
                : OnboardingScreen(
                    key: const ValueKey('onboarding'),
                    onComplete: _onOnboardingComplete,
                  )),
      ),
    );
  }
}
