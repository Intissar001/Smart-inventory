import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';

// Services & Database
import 'db/database_helper.dart';

// Providers
import 'providers/settings_provider.dart';
import 'providers/alerts_provider.dart';
import 'providers/auth_provider.dart';

// Screens
import 'screens/settings_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/auth_screen.dart';

// Global camera variable for local device testing
List<CameraDescription>? cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize physical device cameras
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Camera initialization failed: $e");
  }

  // 2. Initialize local SQLite database instance
  final dbHelper = DatabaseHelper();
  await dbHelper.database;

  // 3. Initialize AuthProvider and restore session
  final authProvider = AuthProvider();
  await authProvider.restoreSession();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => AlertsProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final auth = Provider.of<AuthProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Inventory',

      themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        useMaterial3: true,
      ),

      // If logged in go to dashboard, otherwise go to auth (sign in)
      initialRoute: auth.isLoggedIn ? '/dashboard' : '/auth',
      routes: {
        '/auth':      (context) => const AuthScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/settings':  (context) => const SettingsScreen(),
        '/profile':   (context) => const ProfileScreen(),
      },
    );
  }
}