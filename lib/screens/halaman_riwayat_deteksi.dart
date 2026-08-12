import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/database_helper.dart';
import '../models/deteksi_model.dart';

class HalamanRiwayatDeteksi extends StatefulWidget {
  final bool isEmbedded;

  const HalamanRiwayatDeteksi({super.key, this.isEmbedded = false});

  @override
  State<HalamanRiwayatDeteksi> createState() => _HalamanRiwayatDeteksiState();
}

class _HalamanRiwayatDeteksiState extends State<HalamanRiwayatDeteksi> {
  late Future<List<DeteksiResult>> _riwayatFuture;
  final DateFormat _formatter = DateFormat('dd MMM yyyy • HH:mm');

  @override
  void initState() {
    super.initState();
    _muatRiwayat();
  }

  void _muatRiwayat() {
    _riwayatFuture = DatabaseHelper.instance.getAllDeteksi();
  }

  Future<void> _refresh() async {
    setState(_muatRiwayat);
    await _riwayatFuture;
  }

  @override
  Widget build(BuildContext context) {
    final Widget listContent = RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<DeteksiResult>>(
        future: _riwayatFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF163E21),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Gagal memuat riwayat: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          final data = snapshot.data ?? [];
          if (data.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                Center(
                  child: Text(
                    'Belum ada riwayat deteksi.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: data.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    'RECENT HISTORY LOG',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF8C8A82),
                      letterSpacing: 1.0,
                    ),
                  ),
                );
              }
              return _buildRiwayatItem(data[index - 1]);
            },
          );
        },
      ),
    );

    if (widget.isEmbedded) {
      return listContent;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Deteksi'),
      ),
      body: listContent,
    );
  }

  Widget _buildRiwayatItem(DeteksiResult item) {
    final bool isRetak = item.isRetak;
    final File imageFile = File(item.gambarPath);

    // Pill badge colors
    final Color badgeBg = isRetak ? const Color(0xFFFDF0ED) : const Color(0xFFE8F2E9);
    final Color badgeTextColor = isRetak ? const Color(0xFFC84C3C) : const Color(0xFF163E21);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFE6E4E0),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Image Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imageFile.existsSync()
                  ? Image.file(
                      imageFile,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 64,
                      height: 64,
                      color: const Color(0xFFEBEAE6),
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.grey,
                        size: 24,
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            // Info Column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date & Time
                  Text(
                    _formatter.format(item.tanggal),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8C8A82),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Status Label
                  Text(
                    item.hasilKlasifikasi,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E1E1E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Confidence Pill Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${(item.confidenceScore * 100).toStringAsFixed(1)}% CONFIDENCE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: badgeTextColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Chevron arrow
            const Icon(
              Icons.chevron_right,
              color: Color(0xFFC0BEB8),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
