# Egg Crack Detector

Aplikasi Flutter untuk klasifikasi keretakan cangkang telur ayam berbasis
citra *candling*, menggunakan model CNN MobileNetV2 (TensorFlow Lite).

## Struktur yang sudah dibuat

```
egg_crack_detector/
├── pubspec.yaml
├── assets/model/
│   ├── model.tflite            <- PLACEHOLDER, ganti dengan model asli
│   ├── model.tflite.placeholder <- baca ini, lalu hapus
│   └── labels.txt              <- sudah isi asli: Utuh, Retak
└── lib/
    ├── main.dart
    ├── models/deteksi_model.dart
    ├── database/database_helper.dart      (SQLite: tabel hasil_deteksi)
    ├── services/klasifikasi_service.dart  (load + inference TFLite)
    └── screens/
        ├── halaman_utama.dart          (kamera + upload galeri)
        ├── halaman_hasil_deteksi.dart  (status + confidence score)
        └── halaman_riwayat_deteksi.dart (list riwayat dari SQLite)
```

## Desain & Antarmuka Baru (Modern & Simple)

Aplikasi ini telah diperbarui dengan antarmuka yang bersih, minimalis, dan modern menggunakan skema warna alam:
- **Tema Warna:** Hijau Hutan (*Forest Green* - `0xFF163E21`) sebagai warna utama, dan Krem Hangat (*Warm Cream* - `0xFFFAF8F5`) sebagai latar belakang aplikasi untuk memberikan kesan premium.
- **Navigasi Tab Dinamis:** Menu utama menggunakan *custom bottom navigation bar* dengan indikator titik aktif (*animated active dot*) untuk beralih antara **Home** (Deteksi Telur) dan **Riwayat** (Riwayat Deteksi).
- **Custom Camera View:** Tampilan kamera live preview dibungkus dalam *rounded card* berbingkai halus dengan garis bidik fokus (`[ ]`) di atasnya. Pengambilan foto tidak menggunakan flash kamera secara bawaan (*flash off*).
- **Hasil Deteksi Premium:** Menampilkan status dalam kotak solid hijau tua/merah tua (`STATUS: UTUH` atau `STATUS: RETAK`), dilengkapi indikator bilah kemajuan (*linear progress bar*) tingkat keyakinan, dan *floating badge* persentase keyakinan di atas foto telur.
- **Riwayat Deteksi Premium:** Menggunakan kartu-kartu putih rounded dengan thumbnail foto telur, info tanggal dengan bullet point, status tebal, serta badge pill confidence.

## Cara menjalankan pertama kali

File ini **belum** termasuk folder `android/` dan `ios/` (folder platform
native, ukurannya besar & digenerate otomatis). Langkah setup:

1. Extract project ini, lalu masuk ke foldernya di terminal.
2. Jalankan:
   ```
   flutter create .
   ```
   Ini akan generate folder `android/`, `ios/`, dll di sekitar `lib/` dan
   `pubspec.yaml` yang sudah ada, **tanpa menimpa** kode yang sudah dibuat.
3. Tambahkan permission kamera & penyimpanan di
   `android/app/src/main/AndroidManifest.xml`, taruh di dalam tag
   `<manifest>` (sebelum tag `<application>`):
   ```xml
   <uses-permission android:name="android.permission.CAMERA" />
   <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
   <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
   ```
4. Di file yang sama, cek `minSdkVersion` di
   `android/app/build.gradle` minimal **21** (dibutuhkan plugin `camera`
   dan `tflite_flutter`).
5. Install dependency:
   ```
   flutter pub get
   ```
6. Jalankan ke device/emulator:
   ```
   flutter run
   ```

## Setelah model hasil training siap

1. Rename hasil export dari Colab jadi persis `model.tflite`.
2. Timpa file `assets/model/model.tflite` (yang sekarang masih placeholder).
3. Hapus `assets/model/model.tflite.placeholder` (cuma catatan, tidak dipakai kode).
4. Cek `assets/model/labels.txt` — urutan barisnya HARUS SAMA PERSIS dengan
   urutan `class_indices` saat training (cek di kode training kamu, jangan
   asumsi otomatis `Utuh` index 0).
5. Kalau ukuran input training bukan 224x224, ubah konstanta `inputSize`
   di `lib/services/klasifikasi_service.dart`.
6. Kalau normalisasi pixel saat training bukan `[0,1]` (misal pakai
   `preprocess_input` MobileNetV2 dari Keras yang hasilnya `[-1,1]`), ubah
   bagian `_preprocessImage()` di file yang sama supaya konsisten.
7. `flutter pub get` lagi lalu rebuild aplikasi.

Sebelum langkah di atas dilakukan, aplikasi tetap bisa dijalankan dan
didemokan — Halaman Hasil Deteksi akan menampilkan hasil **acak** disertai
notice oranye "Mode Placeholder", supaya alur & UI tetap bisa dites tanpa
menunggu training kelar.

## Catatan lain

- Fitur riwayat pakai SQLite (`sqflite`), 100% on-device, sesuai Deployment
  Diagram Bab IV (tanpa server).
- Untuk build APK rilis nanti: `flutter build apk --release`.
