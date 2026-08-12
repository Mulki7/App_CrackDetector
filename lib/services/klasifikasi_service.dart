import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Hasil satu kali inference, sebelum disimpan ke database.
class KlasifikasiResult {
  final String label; // "Utuh" atau "Retak"
  final double confidence; // 0.0 - 1.0
  final bool isPlaceholder; // true kalau model asli belum ada

  KlasifikasiResult({
    required this.label,
    required this.confidence,
    this.isPlaceholder = false,
  });
}

/// Membungkus seluruh proses load model MobileNetV2 (.tflite) dan
/// menjalankan inference terhadap citra hasil candling.
class KlasifikasiService {
  KlasifikasiService._internal();
  static final KlasifikasiService instance = KlasifikasiService._internal();

  static const int inputSize = 224;
  static const String modelPath = 'assets/model/model.tflite';
  static const String labelsPath = 'assets/model/labels.txt';

  Interpreter? _interpreter;
  List<String> _labels = ['retak', 'utuh'];
  bool _isModelReady = false;
  final Random _random = Random();

  bool get isModelReady => _isModelReady;

  /// Panggil sekali saat aplikasi start (lihat main.dart).
  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(modelPath);

      final labelsRaw = await rootBundle.loadString(labelsPath);
      final parsedLabels = labelsRaw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parsedLabels.isNotEmpty) _labels = parsedLabels;

      _isModelReady = true;
      // ignore: avoid_print
      print('[KlasifikasiService] Model TFLite berhasil dimuat.');
    } catch (e) {
      _isModelReady = false;
      // ignore: avoid_print
      print('[KlasifikasiService] Model belum tersedia, pakai mode '
          'placeholder. Detail: $e');
    }
  }

  /// Jalankan klasifikasi terhadap file citra hasil capture/upload.
  Future<KlasifikasiResult> klasifikasiCitra(File imageFile) async {
    if (!_isModelReady || _interpreter == null) {
      return _hasilPlaceholder();
    }
    try {
      final input = await _preprocessImage(imageFile);
      final output = List.generate(1, (_) => List.filled(1, 0.0));
      _interpreter!.run(input, output);
      double rawScore = output[0][0];

      String finalLabel;
      double finalConfidence;

      if (rawScore > 0.5) {
        finalLabel = _labels.length > 1 ? _labels[1] : 'utuh';
        finalConfidence = rawScore;
      } else {
        finalLabel = _labels[0];
        finalConfidence = 1.0 - rawScore;
      }

      finalLabel = finalLabel.toLowerCase() == 'utuh' ? 'Utuh' : 'Retak';

      // ========================================================
      // PERBAIKAN: Filter Threshold di bawah 70% (0.70)
      // ========================================================
      if (finalConfidence < 0.70) {
        return KlasifikasiResult(
          label: 'Tidak Dikenali', // Teks status yang akan muncul di UI
          confidence: finalConfidence,
          isPlaceholder: false,
        );
      }

      return KlasifikasiResult(
        label: finalLabel,
        confidence: finalConfidence,
        isPlaceholder: false,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[KlasifikasiService] Gagal inference, fallback placeholder: $e');
      return _hasilPlaceholder();
    }
  }

  /// Resize ke inputSize x inputSize tanpa normalisasi manual.
  /// Layer Lambda preprocess_input di dalam model TFLite yang akan mengubah skala ke [-1, 1].
  Future<List<List<List<List<double>>>>> _preprocessImage(File file) async {
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Gagal decode citra: format tidak didukung');
    }

    final resized = img.copyResize(
      decoded,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    return List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(
          inputSize,
          (x) {
            final pixel = resized.getPixel(x, y);

            // PERBAIKAN: Kirim nilai mentah 0.0 - 255.0 dalam bentuk double.
            // Jangan dibagi 127.5 lagi agar tidak terjadi double preprocessing dengan layer Lambda internal.
            return [
              pixel.r.toDouble(),
              pixel.g.toDouble(),
              pixel.b.toDouble(),
            ];
          },
        ),
      ),
    );
  }

  KlasifikasiResult _hasilPlaceholder() {
    final label = _random.nextBool() ? 'Utuh' : 'Retak';
    final confidence = 0.70 + _random.nextDouble() * 0.29; // 70-99%
    return KlasifikasiResult(
      label: label,
      confidence: confidence,
      isPlaceholder: true,
    );
  }

  void dispose() {
    _interpreter?.close();
  }
}
