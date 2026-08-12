/// Merepresentasikan satu baris data pada tabel `hasil_deteksi` di SQLite.
///
/// Kolom mengikuti desain Class Diagram Bab IV:
/// id (PK), tanggal, gambar_path, hasil_klasifikasi, confidence_score
class DeteksiResult {
  final int? id;
  final DateTime tanggal;
  final String gambarPath;
  final String hasilKlasifikasi; // "Utuh" atau "Retak"
  final double confidenceScore; // 0.0 - 1.0

  DeteksiResult({
    this.id,
    required this.tanggal,
    required this.gambarPath,
    required this.hasilKlasifikasi,
    required this.confidenceScore,
  });

  bool get isRetak => hasilKlasifikasi.toLowerCase() == 'retak';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tanggal': tanggal.toIso8601String(),
      'gambar_path': gambarPath,
      'hasil_klasifikasi': hasilKlasifikasi,
      'confidence_score': confidenceScore,
    };
  }

  factory DeteksiResult.fromMap(Map<String, dynamic> map) {
    return DeteksiResult(
      id: map['id'] as int?,
      tanggal: DateTime.parse(map['tanggal'] as String),
      gambarPath: map['gambar_path'] as String,
      hasilKlasifikasi: map['hasil_klasifikasi'] as String,
      confidenceScore: (map['confidence_score'] as num).toDouble(),
    );
  }
}
