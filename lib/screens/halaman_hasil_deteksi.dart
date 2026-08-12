import 'dart:io';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/deteksi_model.dart';
import '../services/klasifikasi_service.dart';

class HalamanHasilDeteksi extends StatefulWidget {
  final File imageFile;

  const HalamanHasilDeteksi({super.key, required this.imageFile});

  @override
  State<HalamanHasilDeteksi> createState() => _HalamanHasilDeteksiState();
}

class _HalamanHasilDeteksiState extends State<HalamanHasilDeteksi> {
  KlasifikasiResult? _result;
  bool _isLoading = true;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _jalankanDeteksi();
  }

  Future<void> _jalankanDeteksi() async {
    final result =
        await KlasifikasiService.instance.klasifikasiCitra(widget.imageFile);
    if (!mounted) return;
    setState(() {
      _result = result;
      _isLoading = false;
    });
    await _simpanKeRiwayat(result);
  }

  Future<void> _simpanKeRiwayat(KlasifikasiResult result) async {
    if (result.label == 'Tidak Dikenali') {
      return;
    }
    final data = DeteksiResult(
      tanggal: DateTime.now(),
      gambarPath: widget.imageFile.path,
      hasilKlasifikasi: result.label,
      confidenceScore: result.confidence,
    );
    await DatabaseHelper.instance.insertDeteksi(data);
    if (!mounted) return;
    setState(() => _isSaved = true);
  }

  @override
  Widget build(BuildContext context) {
    final String label = _result?.label ?? '';
    final bool isRetak = label.toLowerCase() == 'retak';
    final bool isTidakDikenali = label == 'Tidak Dikenali';

    final Color statusColor = isTidakDikenali
        ? const Color(0xFF8C8A82) // Neutral grey for unrecognized
        : (isRetak ? const Color(0xFFC84C3C) : const Color(0xFF163E21));

    final String statusText = isTidakDikenali
        ? 'STATUS: TIDAK DIKENALI'
        : (isRetak ? 'STATUS: RETAK' : 'STATUS: UTUH');

    final double confidence = _result?.confidence ?? 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hasil Deteksi'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // INPUT: CITRA TELUR label
                    const Text(
                      'INPUT: CITRA TELUR',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8C8A82),
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Image Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: const Color(0xFFE6E4E0), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(5),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(23),
                        child: Stack(
                          children: [
                            Image.file(
                              widget.imageFile,
                              height: 280,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                            // Floating badge
                            if (!_isLoading && _result != null)
                              Positioned(
                                top: 16,
                                right: 16,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${(confidence * 100).toStringAsFixed(1)}% CONFIDENCE',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // RESULT STATUS label
                    const Text(
                      'RESULT STATUS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8C8A82),
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Status Box
                    if (_isLoading)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEBEAE6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFFE6E4E0), width: 1),
                        ),
                        child: const Column(
                          children: [
                            CircularProgressIndicator(color: Color(0xFF163E21)),
                            SizedBox(height: 16),
                            Text(
                              'Menganalisis Citra...',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF163E21),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      if (_result != null && _result!.isPlaceholder)
                        _buildPlaceholderWarning(),
                      // Status display box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withAlpha(38),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            statusText,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Dotted divider or divider line
                      Divider(
                        color: const Color(0xFF163E21).withAlpha(26),
                        thickness: 1,
                      ),
                      const SizedBox(height: 16),
                      // Confidence Score display details
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Confidence Score:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF8C8A82),
                            ),
                          ),
                          Text(
                            '${(confidence * 100).toStringAsFixed(0)} %',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: confidence,
                          minHeight: 8,
                          backgroundColor: const Color(0xFFEBEAE6),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(statusColor),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Saved state text
                      Text(
                        isTidakDikenali
                            ? '✕ Tidak disimpan ke riwayat (objek tidak dikenali)'
                            : (_isSaved
                                ? '✓ Tersimpan ke riwayat deteksi'
                                : 'Menyimpan...'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8C8A82),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Bottom button: KEMBALI KE HALAMAN UTAMA
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF163E21),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text(
                    'KEMBALI KE HALAMAN UTAMA',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD480), width: 1),
      ),
      child: const Text(
        'Mode Demo: Model asli belum terpasang. Hasil di bawah dihasilkan secara acak.',
        style: TextStyle(
          fontSize: 11,
          color: Color(0xFF805C00),
          height: 1.4,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
