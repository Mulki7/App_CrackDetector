import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'halaman_auto_deteksi.dart';
import 'halaman_hasil_deteksi.dart';
import 'halaman_riwayat_deteksi.dart';

class HalamanUtama extends StatefulWidget {
  const HalamanUtama({super.key});

  @override
  State<HalamanUtama> createState() => _HalamanUtamaState();
}

class _HalamanUtamaState extends State<HalamanUtama>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  final ImagePicker _picker = ImagePicker();
  bool _isCameraReady = false;
  String? _cameraError;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Hanya dispose kamera saat benar-benar di-background (paused),
    // BUKAN saat inactive — karena inactive juga dipanggil saat route baru di-push
    // dalam app yang sama (transisi navigasi), yang menyebabkan kamera hilang.
    if (state == AppLifecycleState.paused) {
      if (_cameraController != null &&
          _cameraController!.value.isInitialized) {
        _cameraController!.dispose();
        _cameraController = null;
        if (mounted) setState(() => _isCameraReady = false);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!_isCameraReady) {
        _cameraError = null;
        _setupCamera();
      }
    }
  }

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'Tidak ada kamera terdeteksi di perangkat.');
        return;
      }

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      _initializeControllerFuture = _cameraController!.initialize();
      await _initializeControllerFuture;

      // Matikan flash kamera secara default
      await _cameraController!.setFlashMode(FlashMode.off);

      if (!mounted) return;
      setState(() => _isCameraReady = true);
    } catch (e) {
      setState(() => _cameraError = 'Gagal membuka kamera: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_isCameraReady) return;
    try {
      await _initializeControllerFuture;
      final XFile photo = await _cameraController!.takePicture();
      if (!mounted) return;
      _navigateToHasil(File(photo.path));
    } catch (e) {
      _showError('Gagal mengambil foto: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return; // pengguna batal memilih
      if (!mounted) return;
      _navigateToHasil(File(picked.path));
    } catch (e) {
      _showError('Gagal memuat citra dari galeri: $e');
    }
  }

  void _navigateToHasil(File imageFile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HalamanHasilDeteksi(imageFile: imageFile),
      ),
    ).then((_) {
      // Refresh list riwayat jika user kembali dari halaman hasil
      if (_selectedIndex == 1) {
        setState(() {});
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // Judul per tab (hanya 2 tab di IndexedStack)
  String get _appBarTitle {
    return _selectedIndex == 0 ? 'Deteksi Telur' : 'Riwayat Deteksi';
  }

  /// Buka halaman Auto Deteksi via push.
  /// Kamera utama di-dispose sepenuhnya sebelum push agar tidak konflik,
  /// lalu di-setup ulang setelah user kembali.
  Future<void> _bukaAutoDeteksi() async {
    // Dispose kamera utama dulu agar kamera Auto bebas menggunakannya
    if (_cameraController != null) {
      final ctrl = _cameraController!;
      _cameraController = null;
      if (mounted) setState(() => _isCameraReady = false);
      try {
        await ctrl.dispose();
      } catch (_) {}
    }

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HalamanAutoDeteksi()),
    );

    // Tunggu sebentar agar HalamanAutoDeteksi selesai dispose kameranya
    // sebelum kita coba initialize kamera utama lagi.
    // Flutter memanggil dispose() route lama secara async setelah push() return.
    await Future.delayed(const Duration(milliseconds: 700));

    // Setelah kembali, setup ulang kamera utama
    if (mounted) {
      _cameraError = null;
      await _setupCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitle),
        leading: _selectedIndex != 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedIndex = 0;
                  });
                },
              )
            : null,
        centerTitle: true,
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            Column(
              children: [
                Expanded(child: _buildCameraPreview()),
                _buildCatatanPencahayaan(),
                _buildControlBar(),
              ],
            ),
            HalamanRiwayatDeteksi(
              isEmbedded: true,
              key: ValueKey(_selectedIndex),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _cameraError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    Widget content;
    if (!_isCameraReady || _cameraController == null) {
      content = const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF163E21),
        ),
      );
    } else {
      // Ambil aspect ratio sensor kamera (umumnya > 1.0 karena berupa landscape, misal 1.77 untuk 16:9).
      // Kita pastikan nilainya > 1.0 agar perkalian menghasilkan tinggi portrait yang benar.
      double cameraAspectRatio = _cameraController!.value.aspectRatio;
      if (cameraAspectRatio < 1.0) {
        cameraAspectRatio = 1.0 / cameraAspectRatio;
      }

      content = Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: 100,
              height: 100 * cameraAspectRatio,
              child: CameraPreview(_cameraController!),
            ),
          ),
          // Focus corners overlay
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: CustomPaint(
                painter: FocusCornersPainter(color: Colors.white.withAlpha(204)),
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
            color: const Color(0xFFEBEAE6), // Warm greyish background
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

  Widget _buildCatatanPencahayaan() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF0EC), // light green-grey color
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: Color(0xFF163E21),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF163E21),
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: 'Note: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: 'Pastikan pencahayaan cukup dan posisi telur berada di tengah grid kamera untuk akurasi terbaik.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      height: 90,
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Gallery button
          GestureDetector(
            onTap: _pickFromGallery,
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF163E21),
              ),
              child: const Icon(
                Icons.image_outlined,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          // Capture button
          GestureDetector(
            onTap: _isCameraReady ? _capturePhoto : null,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF163E21),
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.all(4),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isCameraReady ? const Color(0xFF163E21) : Colors.grey,
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
          // Empty spacer to center the capture button by mirroring the gallery button width
          const SizedBox(width: 56),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8F5),
        border: Border(
          top: BorderSide(
            color: const Color(0xFF163E21).withAlpha(20),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(0, Icons.home_outlined, 'Home'),
            _buildNavItem(1, Icons.history, 'Riwayat'),
            _buildNavItemAuto(),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final bool isSelected = _selectedIndex == index;
    final Color color = isSelected ? const Color(0xFF163E21) : const Color(0xFF163E21).withAlpha(102);

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 4),
            // The tiny active dot below the label
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? const Color(0xFF163E21) : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Nav item khusus untuk tab Auto Deteksi.
  /// Menggunakan Navigator.push agar tidak ada dua kamera aktif bersamaan.
  Widget _buildNavItemAuto() {
    const Color dimColor = Color(0xFF163E21);

    return GestureDetector(
      onTap: _bukaAutoDeteksi,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined,
                color: dimColor.withAlpha(102), size: 24),
            const SizedBox(height: 4),
            Text(
              'Auto',
              style: TextStyle(
                color: dimColor.withAlpha(102),
                fontSize: 11,
                fontWeight: FontWeight.normal,
              ),
            ),
            const SizedBox(height: 4),
            const SizedBox(width: 4, height: 4),
          ],
        ),
      ),
    );
  }
}

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
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - lineLength, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, lineLength), paint);

    // Bottom-Left corner
    canvas.drawLine(Offset(0, size.height), Offset(lineLength, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - lineLength), paint);

    // Bottom-Right corner
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - lineLength, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - lineLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
