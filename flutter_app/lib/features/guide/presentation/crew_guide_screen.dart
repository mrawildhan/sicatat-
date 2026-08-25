import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';

class CrewGuideScreen extends StatelessWidget {
  const CrewGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/dashboard'),
          title: const Text(
            'Buku panduan SICATAT',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: const <Widget>[
            _GuideSection(
              'A. Pencatatan temperature',
              'Buka tab Temperature, lalu pilih New sheet. Tentukan tanggal pemeriksaan dan shift yang sesuai. Satu sheet hanya digunakan untuk satu kombinasi tanggal, shift, dan site.',
            ),
            _GuideSection(
              'B. Isi Round 1 dan Round 2',
              'Pilih unit serta sisi Barat atau Timur, lalu simpan setiap sisi. Waktu round akan tercatat otomatis saat data pertama disimpan. Sheet boleh dibiarkan sebagai draft dan dilanjutkan sebelum shift berakhir.',
            ),
            _GuideSection(
              'C. Pilih kondisi unit',
              'Pilih Operating untuk mengisi seluruh titik temperature. Jika Not operating atau Not accessible, isi alasan kondisi tersebut. Jangan menggunakan nilai suhu sebagai pengganti alasan.',
            ),
            _GuideSection(
              'D. Perhatikan warna temperature',
              'Hijau berarti di bawah 60°C. Oranye menunjukkan 60–69°C dan perlu perhatian. Merah menunjukkan 70°C atau lebih dan harus segera dilaporkan mengikuti prosedur operasi.',
            ),
            _GuideSection(
              'E. Ringkasan dan pengiriman sheet',
              'Buka Sheet summary untuk melihat seluruh bagian yang sudah atau belum terisi. Kartu merah dapat ditekan untuk menuju data yang masih kosong. Submit dilakukan setelah data siap; sheet yang telah diverifikasi terkunci.',
            ),
            _GuideSection(
              'F. Reminder operasional',
              'Pengguna yang mendapat akses Reminder dapat menambahkan judul, aset, tindakan, PIC, lokasi, tanggal jatuh tempo, prioritas, penerima, dan jadwal email. Pilih H-30, H-14, H-7, H-1, atau hari jatuh tempo sesuai kebutuhan.',
            ),
            _GuideSection(
              'G. Menyelesaikan reminder',
              'Setelah tindakan selesai, tekan Mark complete dan masukkan catatan bila diperlukan. Gunakan Reopen jika pekerjaan harus dibuka kembali. Riwayat pengiriman email dan perubahan dapat dilihat melalui ikon riwayat.',
            ),
            _GuideSection(
              'H. Hak akses dan koneksi',
              'SICATAT bekerja online-only. Menu yang tampil mengikuti peran akun dan site penugasan. Jika data tidak dapat dimuat, periksa koneksi internet lalu tekan Refresh; jangan menghapus aplikasi.',
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection(this.title, this.description);

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: AppColors.greenDark,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(color: AppColors.muted, height: 1.45),
          ),
        ],
      ),
    ),
  );
}
