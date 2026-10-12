import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/screens/splashscreen.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Phone ledger UI is designed for portrait (prevents squeezed layouts).
  // Both start-up steps run together, so the first screen appears sooner.
  await Future.wait([
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    Firebase.initializeApp(),
  ]);

  runApp(
    MultiProvider(
      providers: [
        // lazy: false -> the local database opens during the splash screen,
        // so the main screen never has to show a loading page.
        ChangeNotifierProvider(lazy: false, create: (context) => Dbprovider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppBrand.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // Keep layouts intact with very large system font sizes.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: child!,
      ),
      home: const Splashscreen(),
    );
  }
}
