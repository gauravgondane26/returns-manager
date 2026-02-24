import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ReturnsManagerApp());
}

class ReturnsManagerApp extends StatelessWidget {
  const ReturnsManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Returns Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const BootstrapStatusPage(),
    );
  }
}

class BootstrapStatusPage extends StatelessWidget {
  const BootstrapStatusPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Returns Manager')),
      body: const Center(child: Text('Firebase connected')),
    );
  }
}
