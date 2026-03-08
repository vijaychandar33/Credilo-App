import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/dashboard_home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'config/supabase_config.dart';
import 'utils/app_themes.dart';
import 'widgets/internet_status_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    debugPrint('✅ Supabase initialized successfully');
  } catch (e) {
    debugPrint('❌ Error initializing Supabase: $e');
  }

  await ThemeService.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
    ThemeService.notifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeService.notifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkAuth() async {
    final isAuth = await _authService.checkAuth();
    if (mounted) {
      setState(() {
        _isAuthenticated = isAuth;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pre-login: always dark. Post-login: use stored preference (default dark).
    final themeMode = _isAuthenticated ? ThemeService.current : ThemeMode.dark;

    return MaterialApp(
      title: 'credilo',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      home: _isLoading
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _isAuthenticated
              ? const DashboardHomeScreen()
              : const LoginScreen(),
      builder: (context, child) {
        return InternetStatusOverlay(
          child: child ?? const SizedBox.shrink(),
        );
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
