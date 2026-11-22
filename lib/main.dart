import 'package:material_ui/material_ui.dart';

import 'app/app_platform.dart';
import 'app/home_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _darkMode = false;
  String _currencyCode = 'PHP';

  @override
  void initState() {
    super.initState();
    _loadAppearance();
  }

  Future<void> _loadAppearance() async {
    try {
      final darkMode = await AppPlatform.darkMode();
      if (mounted) setState(() => _darkMode = darkMode);
    } catch (_) {
      // Keep the established light appearance if preferences cannot be read.
    }
    try {
      final currencyCode = await AppPlatform.currencyCode();
      if (mounted) setState(() => _currencyCode = currencyCode);
    } catch (_) {
      // Keep PHP when the stored currency is unreadable or unsupported.
    }
  }

  Future<bool> _setDarkMode(bool enabled) async {
    final previous = _darkMode;
    setState(() => _darkMode = enabled);
    try {
      final saved = await AppPlatform.setDarkMode(enabled);
      if (!saved && mounted) setState(() => _darkMode = previous);
      return saved;
    } catch (_) {
      if (mounted) setState(() => _darkMode = previous);
      return false;
    }
  }

  Future<bool> _setCurrencyCode(String code) async {
    final previous = _currencyCode;
    setState(() => _currencyCode = code);
    try {
      final saved = await AppPlatform.setCurrencyCode(code);
      if (!saved && mounted) setState(() => _currencyCode = previous);
      return saved;
    } catch (_) {
      if (mounted) setState(() => _currencyCode = previous);
      return false;
    }
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF176B60),
      brightness: brightness,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Splitter',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
    home: HomeScreen(
      darkMode: _darkMode,
      onDarkModeChanged: _setDarkMode,
      currencyCode: _currencyCode,
      onCurrencyChanged: _setCurrencyCode,
    ),
  );
}
