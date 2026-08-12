import 'package:flutter/material.dart';

import 'screens/halaman_utama.dart';
import 'services/klasifikasi_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load model MobileNetV2 (.tflite) sekali di awal.
  // Kalau model asli belum ada, otomatis jatuh ke mode placeholder.
  await KlasifikasiService.instance.loadModel();

  runApp(const EggCrackDetectorApp());
}

class EggCrackDetectorApp extends StatelessWidget {
  const EggCrackDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deteksi Keretakan Telur',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF163E21),
          primary: const Color(0xFF163E21),
        ),
        scaffoldBackgroundColor: const Color(0xFFFAF8F5),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFAF8F5),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Color(0xFF163E21)),
          titleTextStyle: TextStyle(
            color: Color(0xFF163E21),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      home: const HalamanUtama(),
    );
  }
}
