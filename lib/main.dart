import 'package:flutter/material.dart';

void main() {
  runApp(const DeveloperApp());
}

class DeveloperApp extends StatelessWidget {
  const DeveloperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'developer-app',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const Scaffold(
        body: Center(child: Text('developer-app')),
      ),
    );
  }
}
