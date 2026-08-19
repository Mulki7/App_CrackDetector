import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/auto_deteksi_service.dart';
import '../services/klasifikasi_service.dart';
import 'halaman_hasil_deteksi.dart';

// ──────────────────────────────────────────────────────────
// State Machine
// ──────────────────────────────────────────────────────────

enum _DeteksiStatus {
  loading,
  mencariObjek,
  objekTerdeteksi,
  menungguStabil,
  mengambilGambar,
}

// ──────────────────────────────────────────────────────────
// Widget Utama
// ──────────────────────────────────────────────────────────

class HalamanAutoDeteksi extends StatefulWidget {
  const HalamanAutoDeteksi({super.key});

  @override
  State<HalamanAutoDeteksi> createState() => _HalamanAutoDeteksiState();
}

class _HalamanAutoDeteksiState extends State<HalamanAutoDeteksi>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // ── Kamera ──
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isStreaming = false;

  // ── Deteksi State ──
  _DeteksiStatus _status = _DeteksiStatus.loading;
  String _currentLabel = '';
  double _currentConfidence = 0.0;
  int _consecutiveCount = 0;
  String _lastLabel = '';
  bool _isCapturing = false;
  bool _isProcessingFrame = false;
  int? _lastFrameMs;
  bool _isDeteksiAktif = true; // toggle start/stop stream

  // Menyimpan confidence score tiap frame yang lolos threshold (maks _requiredFrames entri)
  final List<double> _frameConfidences = [];

  // ── Animasi ──
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ── Konstanta ──
  static const int _requiredFrames = 3;
  static const double _confidenceThreshold = 0.6;
  static const int _frameIntervalMs = 500;

  // Tema warna utama
  static const Color _primaryColor = Color(0xFF163E21);
  static const Color _bgColor = Color(0xFFFAF8F5);
  static const Color _cardColor = Color(0xFFEBF0EC);

  // ──────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupPulseAnimation();
    _initAll();
  }

  void _setupPulseAnimation() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initAll() async {
    await AutoDeteksiService.instance.loadModel();
    await _setupCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.paused) {
      _doStopStream();
      _cameraController?.dispose();
      _cameraController = null;
      if (mounted) setState(() => _isCameraReady = false);
    } else if (state == AppLifecycleState.resumed && !_isCameraReady) {
      _setupCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _doStopStream();
    _cameraController?.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────
  // Kamera
  // ──────────────────────────────────────────────────────

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      await _cameraController!.setFlashMode(FlashMode.off);

      if (!mounted) return;
      setState(() {
        _isCameraReady = true;
        _status = _DeteksiStatus.mencariObjek;
      });

      _startStream();
    } catch (e) {
      // ignore: avoid_print
      print('[HalamanAutoDeteksi] Gagal setup kamera: $e');
    }
  }

  void _startStream() {
    if (_isStreaming) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    _consecutiveCount = 0;
    _lastLabel = '';
    _frameConfidences.clear();
    _isStreaming = true;
    _cameraController!.startImageStream(_onFrame);
  }

  void _doStopStream() {
    if (!_isStreaming) return;
    _isStreaming = false;
    try {
      _cameraController?.stopImageStream();
    } catch (_) {}
  }

  Future<void> _stopStreamAsync() async {
    if (!_isStreaming) return;
    _isStreaming = false;
    try {
      await _cameraController?.stopImageStream();
    } catch (_) {}
  }

  // ──────────────────────────────────────────────────────
  // Frame Processing (Image Stream Callback)
  // ──────────────────────────────────────────────────────

  Future<void> _onFrame(CameraImage frame) async {
    // Guard: abaikan frame jika sedang capture atau sudah ada frame diproses
    if (_isCapturing || _isProcessingFrame) return;

    // Throttle: minimal _frameIntervalMs ms antar frame
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastFrameMs != null && nowMs - _lastFrameMs! < _frameIntervalMs) {
      return;
    }
    _lastFrameMs = nowMs;

    _isProcessingFrame = true;

    try {
      final result = await AutoDeteksiService.instance.klasifikasiFrame(frame);

      // Re-check setelah await selesai (state mungkin berubah)
      if (!mounted || _isCapturing) return;

      if (result == null ||
          result.confidence < _confidenceThreshold ||
          result.label == 'Tidak Dikenali') {
        // Confidence rendah (< 85%) atau tidak dikenali → reset ke pencarian secara senyap (tanpa pop up)
        setState(() {
          _currentConfidence = result?.confidence ?? 0.0;
          _currentLabel = '';
          _consecutiveCount = 0;
          _lastLabel = '';
          _frameConfidences.clear();
          _status = _DeteksiStatus.mencariObjek;
        });
        return;
      }

      // ── Confidence ≥ 85%: akumulasi untuk rata-rata ──
      if (result.label == _lastLabel) {
        _consecutiveCount++;
        _frameConfidences.add(result.confidence);
      } else {
        _consecutiveCount = 1;
        _lastLabel = result.label;
        _frameConfidences
          ..clear()
          ..add(result.confidence);
      }

      setState(() {
        _currentLabel = result.label;
        _currentConfidence = result.confidence;

        if (_consecutiveCount == 1) {
          _status = _DeteksiStatus.objekTerdeteksi;
        } else if (_consecutiveCount < _requiredFrames) {
          _status = _DeteksiStatus.menungguStabil;
        } else {
          _status = _DeteksiStatus.mengambilGambar;
        }
      });

      // Trigger capture ketika sudah stabil
      if (_consecutiveCount >= _requiredFrames) {
        await _captureAndNavigate();
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  // ──────────────────────────────────────────────────────
  // Capture & Navigate
  // ──────────────────────────────────────────────────────

  Future<void> _captureAndNavigate() async {
    // Guard mencegah multiple capture
    if (_isCapturing) return;
    _isCapturing = true;

    try {
      // 1. Hentikan stream terlebih dahulu
      await _stopStreamAsync();

      // 2. Beri jeda singkat agar driver kamera selesai
      await Future.delayed(const Duration(milliseconds: 200));

      if (!mounted) return;

      // 3. Ambil foto resolusi penuh
      final XFile photo = await _cameraController!.takePicture();
      final File photoFile = File(photo.path);

      if (!mounted) return;

      // 4. Gate: jalankan inference pada foto hasil capture.
      //    Ini memastikan hasil yang ditampilkan di HalamanHasilDeteksi
      //    konsisten dengan threshold 85%. Kalau foto gagal (hasilnya
      //    berbeda dari stream karena perbedaan resolusi/format), deteksi
      //    ulang tanpa navigasi.
      final inferenceResult =
          await KlasifikasiService.instance.klasifikasiCitra(photoFile);

      if (!mounted) return;

      // Cek rata-rata confidence dari frame stream
      final double avgFrameConfidence = _frameConfidences.isNotEmpty
          ? _frameConfidences.reduce((a, b) => a + b) / _frameConfidences.length
          : 0.0;

      final bool fotoLolos = inferenceResult.label != 'Tidak Dikenali' &&
          inferenceResult.confidence >= _confidenceThreshold &&
          avgFrameConfidence >= _confidenceThreshold;

      if (!fotoLolos) {
        // Foto tidak memenuhi threshold → reset senyap, deteksi ulang
        // ignore: avoid_print
        print('[AutoDeteksi] Foto tidak lolos gate (conf foto: '
            '${(inferenceResult.confidence * 100).toStringAsFixed(1)}%, '
            'avg frame: ${(avgFrameConfidence * 100).toStringAsFixed(1)}%). '
            'Deteksi ulang.');
        if (mounted) {
          setState(() {
            _status = _DeteksiStatus.mencariObjek;
            _currentLabel = '';
            _currentConfidence = 0.0;
            _consecutiveCount = 0;
            _lastLabel = '';
            _frameConfidences.clear();
          });
          _isCapturing = false;
          _startStream();
        }
        return;
      }

      // 5. Lolos gate → navigasi ke halaman hasil
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HalamanHasilDeteksi(imageFile: photoFile),
        ),
      );

      // 6. User kembali → reset state dan mulai stream lagi (jika deteksi masih aktif)
      if (mounted) {
        setState(() {
          _status = _DeteksiStatus.mencariObjek;
          _currentLabel = '';
          _currentConfidence = 0.0;
          _consecutiveCount = 0;
          _lastLabel = '';
          _frameConfidences.clear();
        });
        _isCapturing = false;
        if (_isDeteksiAktif) _startStream();
      }
    } catch (e) {
      // ignore: avoid_print
      print('[HalamanAutoDeteksi] Error capture: $e');
      _isCapturing = false;
      if (mounted) {
        setState(() {
          _status = _DeteksiStatus.mencariObjek;
          _frameConfidences.clear();
        });
        if (_isDeteksiAktif) _startStream();
      }
    }
  }

  // ──────────────────────────────────────────────────────
  // Toggle Start / Stop Deteksi
  // ──────────────────────────────────────────────────────

  void _toggleDeteksi() {
    if (_isDeteksiAktif) {
      // Hentikan → stop stream, reset state deteksi
      _doStopStream();
      setState(() {
        _isDeteksiAktif = false;
        _status = _DeteksiStatus.mencariObjek;
        _currentLabel = '';
        _currentConfidence = 0.0;
        _consecutiveCount = 0;
        _lastLabel = '';
        _frameConfidences.clear();
      });
    } else {
      // Mulai → restart stream
      setState(() => _isDeteksiAktif = true);
      _startStream();
    }
  }
  // ──────────────────────────────────────────────────────

  Color _getCornerColor() {
    switch (_status) {
      case _DeteksiStatus.loading:
      case _DeteksiStatus.mencariObjek:
        return Colors.white;
      case _DeteksiStatus.objekTerdeteksi:
      case _DeteksiStatus.menungguStabil:
        return _currentLabel == 'Retak'
            ? const Color(0xFFE53935)
            : const Color(0xFF2E7D32);
      case _DeteksiStatus.mengambilGambar:
        return const Color(0xFF2E7D32);
    }
  }

  Color _getLabelColor(String label) {
    if (label == 'Retak') return const Color(0xFFE53935);
    if (label == 'Utuh') return const Color(0xFF2E7D32);
    return _primaryColor;
  }

  ({String text, Color color, IconData icon}) _getStatusInfo() {
    switch (_status) {
      case _DeteksiStatus.loading:
        return (
          text: 'Memuat kamera...',
          color: _primaryColor.withAlpha(153),
          icon: Icons.hourglass_empty_rounded,
        );
      case _DeteksiStatus.mencariObjek:
        return (
          text: 'Mencari objek...',
          color: _primaryColor.withAlpha(153),
          icon: Icons.search_rounded,
        );
      case _DeteksiStatus.objekTerdeteksi:
        return (
          text: 'Objek terdeteksi...',
          color: const Color(0xFFF57F17),
          icon: Icons.radio_button_checked_rounded,
        );
      case _DeteksiStatus.menungguStabil:
        return (
          text: 'Menunggu objek stabil...',
          color: const Color(0xFFF57F17),
          icon: Icons.center_focus_strong_rounded,
        );
      case _DeteksiStatus.mengambilGambar:
        return (
          text: 'Mengambil gambar...',
          color: const Color(0xFF2E7D32),
          icon: Icons.camera_alt_rounded,
        );
    }
  }

  // ──────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: const Text('Auto Deteksi'),
        centerTitle: true,
        backgroundColor: _bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _primaryColor),
        titleTextStyle: const TextStyle(
          color: _primaryColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // ── Area kamera ──
            Expanded(
              child: _buildCameraPreview(),
            ),
            // ── Catatan ──
            _buildCatatanHint(),
            // ── Status panel ──
            _buildStatusPanel(),
            // ── Tombol Start / Stop ──
            _buildDeteksiButton(),
          ],
        ),
      ),
    );
  }

  // ── Camera Preview ──

  Widget _buildCameraPreview() {
    Widget content;

    if (!_isCameraReady || _cameraController == null) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: _primaryColor),
            const SizedBox(height: 16),
            Text(
              'Memuat kamera...',
              style: TextStyle(
                color: _primaryColor.withAlpha(153),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    } else {
      double camAr = _cameraController!.value.aspectRatio;
      if (camAr < 1.0) camAr = 1.0 / camAr;

      content = Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: 100,
              height: 100 * camAr,
              child: CameraPreview(_cameraController!),
            ),
          ),
          // Focus corners overlay (sama persis letaknya dengan halaman home)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, _) {
                  final cornerColor = _getCornerColor();
                  final opacityValue =
                      (_status == _DeteksiStatus.mencariObjek ||
                              _status == _DeteksiStatus.loading)
                          ? _pulseAnimation.value
                          : 1.0;

                  return CustomPaint(
                    painter: FocusCornersPainter(
                      color:
                          cornerColor.withAlpha((204 * opacityValue).round()),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEBEAE6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE0DDD8), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: content,
          ),
        ),
      ),
    );
  }

  // ── Catatan Hint ──

  Widget _buildCatatanHint() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded,
              color: _primaryColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Arahkan kamera ke telur. Deteksi akan berjalan otomatis saat objek terdeteksi.',
              style: TextStyle(
                fontSize: 12,
                color: _primaryColor.withAlpha(204),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status Panel ──

  Widget _buildStatusPanel() {
    // Jika deteksi dihentikan, tampilkan pesan khusus
    if (!_isDeteksiAktif) {
      return Container(
        margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _primaryColor.withAlpha(25),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.pause_circle_outline_rounded,
                color: _primaryColor.withAlpha(128), size: 18),
            const SizedBox(width: 10),
            Text(
              'Deteksi dihentikan. Tekan Mulai untuk melanjutkan.',
              style: TextStyle(
                fontSize: 13,
                color: _primaryColor.withAlpha(153),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final info = _getStatusInfo();
    final labelColor = _getLabelColor(_currentLabel);
    final hasDetection = _currentLabel.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _primaryColor.withAlpha(25),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Baris atas: status text + label badge ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(info.icon, color: info.color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  info.text,
                  style: TextStyle(
                    color: info.color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasDetection) ...[
                const SizedBox(width: 8),
                _buildLabelBadge(_currentLabel, labelColor),
              ],
            ],
          ),

          // ── Confidence bar ──
          if (hasDetection) ...[
            const SizedBox(height: 14),
            _buildConfidenceBar(labelColor),
            const SizedBox(height: 12),
            _buildFrameCounter(labelColor),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'Tempatkan telur di dalam bingkai kamera untuk memulai deteksi.',
              style: TextStyle(
                fontSize: 11,
                color: _primaryColor.withAlpha(102),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tombol Start / Stop Deteksi ──

  Widget _buildDeteksiButton() {
    final bool aktif = _isDeteksiAktif;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isCameraReady && !_isCapturing ? _toggleDeteksi : null,
        icon: Icon(
          aktif ? Icons.stop_rounded : Icons.play_arrow_rounded,
          size: 22,
        ),
        label: Text(
          aktif ? 'Hentikan Deteksi' : 'Mulai Deteksi',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: aktif
              ? const Color(0xFFC84C3C) // merah saat aktif (stop)
              : _primaryColor, // hijau saat nonaktif (start)
          foregroundColor: Colors.white,
          disabledBackgroundColor: _primaryColor.withAlpha(60),
          disabledForegroundColor: Colors.white54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildLabelBadge(String label, Color color) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(115), width: 1),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildConfidenceBar(Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Confidence Score',
              style: TextStyle(
                color: _primaryColor.withAlpha(128),
                fontSize: 11,
                letterSpacing: 0.4,
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                '${(_currentConfidence * 100).toStringAsFixed(1)}%',
                key: ValueKey(_currentConfidence.toStringAsFixed(1)),
                style: TextStyle(
                  color: accentColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: _currentConfidence),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 7,
              backgroundColor: _primaryColor.withAlpha(26),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFrameCounter(Color accentColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Stabilisasi: ',
          style: TextStyle(
            color: _primaryColor.withAlpha(102),
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 8),
        ...List.generate(_requiredFrames, (i) {
          final active = i < _consecutiveCount;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 28 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: active ? accentColor : _primaryColor.withAlpha(46),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
        const SizedBox(width: 8),
        Text(
          '$_consecutiveCount/$_requiredFrames',
          style: TextStyle(
            color: _primaryColor.withAlpha(102),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────
// Custom Painter: Focus Corners Overlay
// ──────────────────────────────────────────────────────────

class FocusCornersPainter extends CustomPainter {
  final Color color;
  FocusCornersPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    const double lineLength = 24.0;

    // Top-Left corner
    canvas.drawLine(const Offset(0, 0), const Offset(lineLength, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, lineLength), paint);

    // Top-Right corner
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width - lineLength, 0), paint);
    canvas.drawLine(
        Offset(size.width, 0), Offset(size.width, lineLength), paint);

    // Bottom-Left corner
    canvas.drawLine(
        Offset(0, size.height), Offset(lineLength, size.height), paint);
    canvas.drawLine(
        Offset(0, size.height), Offset(0, size.height - lineLength), paint);

    // Bottom-Right corner
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width - lineLength, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width, size.height - lineLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
