
import 'package:flutter/material.dart';
import 'services/hermes_api.dart';
import 'pages/login_page.dart';

final hermesApi = HermesApi();

void main() {
  runApp(const HermesControllerApp());
}

class HermesControllerApp extends StatelessWidget {
  const HermesControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const LoginPage(),
    );
  }
}
