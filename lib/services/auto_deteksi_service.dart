import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'klasifikasi_service.dart';

/// Service untuk klasifikasi frame-per-frame menggunakan [startImageStream].
///
/// Memiliki [Interpreter] tersendiri agar [KlasifikasiService] tidak dimodifikasi.
/// Singleton — dipanggil sekali dan tetap hidup selama siklus aplikasi.
class AutoDeteksiService {
  AutoDeteksiService._internal();
  static final AutoDeteksiService instance = AutoDeteksiService._internal();

  static const int _inputSize = 224;
  static const String _modelPath = 'assets/model/model.tflite';
  static const String _labelsPath = 'assets/model/labels.txt';

  Interpreter? _interpreter;
  List<String> _labels = ['retak', 'utuh'];
  bool _isReady = false;

  bool get isReady => _isReady;

  // ──────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────

  /// Muat model TFLite. Idempotent — tidak memuat ulang jika sudah siap.
  Future<void> loadModel() async {
    if (_isReady && _interpreter != null) return;
    try {
      _interpreter = await Interpreter.fromAsset(_modelPath);

      final raw = await rootBundle.loadString(_labelsPath);
      final parsed = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parsed.isNotEmpty) _labels = parsed;

      _isReady = true;
      // ignore: avoid_print
      print('[AutoDeteksiService] Model berhasil dimuat.');
    } catch (e) {
      _isReady = false;
      // ignore: avoid_print
      print('[AutoDeteksiService] Gagal memuat model: $e');
    }
  }

  /// Jalankan inferensi pada satu [CameraImage] frame dari image stream.
  ///
  /// Mengembalikan [KlasifikasiResult] jika berhasil, atau null jika:
  /// - service belum siap
  /// - format frame tidak didukung
  /// - terjadi error saat inferensi
  Future<KlasifikasiResult?> klasifikasiFrame(CameraImage frame) async {
    if (!_isReady || _interpreter == null) return null;
    try {
      final rgb = _convertToRgb(frame);
      if (rgb == null) return null;

      final resized = img.copyResize(
        rgb,
        width: _inputSize,
        height: _inputSize,
        interpolation: img.Interpolation.linear,
      );

      // Bangun tensor input [1, 224, 224, 3] dengan nilai pixel 0–255
      // (layer Lambda di dalam model yang melakukan normalisasi ke [-1,1])
      final input = List.generate(
        1,
        (_) => List.generate(
          _inputSize,
          (y) => List.generate(
            _inputSize,
            (x) {
              final pixel = resized.getPixel(x, y);
              return [
                pixel.r.toDouble(),
                pixel.g.toDouble(),
                pixel.b.toDouble(),
              ];
            },
          ),
        ),
      );

      final output = List.generate(1, (_) => List.filled(1, 0.0));
      _interpreter!.run(input, output);

      final double rawScore = output[0][0];
      final String rawLabel;
      final double confidence;

      // Index 0 = retak, index 1 = utuh (sigmoid: mendekati 1.0 → utuh)
      if (rawScore > 0.5) {
        rawLabel = _labels.length > 1 ? _labels[1] : 'utuh';
        confidence = rawScore;
      } else {
        rawLabel = _labels[0];
        confidence = 1.0 - rawScore;
      }

      final label = rawLabel.toLowerCase() == 'utuh' ? 'Utuh' : 'Retak';
      return KlasifikasiResult(label: label, confidence: confidence);
    } catch (e) {
      // ignore: avoid_print
      print('[AutoDeteksiService] Error inferensi frame: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────
  // Konversi Format Frame
  // ──────────────────────────────────────────────

  img.Image? _convertToRgb(CameraImage frame) {
    try {
      if (frame.format.group == ImageFormatGroup.yuv420) {
        return _yuv420ToRgb(frame);
      } else if (frame.format.group == ImageFormatGroup.bgra8888) {
        return _bgra8888ToRgb(frame);
      }
      // ignore: avoid_print
      print(
          '[AutoDeteksiService] Format frame tidak didukung: ${frame.format.group}');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[AutoDeteksiService] Gagal konversi frame: $e');
      return null;
    }
  }

  /// Konversi YUV420 (Android) ke RGB.
  ///
  /// Menggunakan downsampling 2x ([step] = 2) untuk mengurangi jumlah pixel
  /// yang diproses dari ~1x ke ~0.25x resolusi asli, mempercepat konversi
  /// tanpa berdampak signifikan pada akurasi klasifikasi biner.
  img.Image _yuv420ToRgb(CameraImage frame) {
    const int step = 2;
    final int w = frame.width;
    final int h = frame.height;
    final int outW = w ~/ step;
    final int outH = h ~/ step;

    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final int yRowStride = yPlane.bytesPerRow;
    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final out = img.Image(width: outW, height: outH);

    for (int sy = 0; sy < h; sy += step) {
      for (int sx = 0; sx < w; sx += step) {
        // Klamping untuk keamanan jika bytesPerRow != width
        final int yIdx = (sy * yRowStride + sx).clamp(0, yBytes.length - 1);
        final int uvIdx = ((sy >> 1) * uvRowStride + (sx >> 1) * uvPixelStride)
            .clamp(0, uBytes.length - 1);

        final int y = yBytes[yIdx] & 0xFF;
        final int u = (uBytes[uvIdx] & 0xFF) - 128;
        final int v = (vBytes[uvIdx] & 0xFF) - 128;

        // Rumus konversi YCbCr → RGB (ITU-R BT.601)
        final int r = (y + 1.402 * v).round().clamp(0, 255);
        final int g = (y - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
        final int b = (y + 1.772 * u).round().clamp(0, 255);

        out.setPixelRgb(sx ~/ step, sy ~/ step, r, g, b);
      }
    }
    return out;
  }

  /// Konversi BGRA8888 (iOS) ke RGB menggunakan package image.
  img.Image _bgra8888ToRgb(CameraImage frame) {
    return img.Image.fromBytes(
      width: frame.width,
      height: frame.height,
      bytes: frame.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
  }
}
