import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';

/// One topic inside a guide group.
class _GuideEntry {
  const _GuideEntry(this.title, this.description);

  final String title;
  final String description;
}

/// A menu-sized group of topics.
///
/// The screen and the downloadable PDF are both built from this one list, so
/// the two can no longer drift apart as the app gains features.
class _GuideGroupData {
  const _GuideGroupData({
    required this.title,
    required this.icon,
    required this.entries,
  });

  final String title;
  final IconData icon;
  final List<_GuideEntry> entries;
}

const List<_GuideGroupData> _guideGroups = <_GuideGroupData>[
  _GuideGroupData(
    title: 'Dasar penggunaan',
    icon: Icons.play_circle_outline_rounded,
    entries: <_GuideEntry>[
      _GuideEntry(
        'Masuk aplikasi',
        'Masuk dengan NIK dan PIN masing-masing. Jangan berbagi PIN. Akun dibuat oleh admin; tidak ada pendaftaran sendiri.',
      ),
      _GuideEntry(
        'Menemukan menu',
        'Ada empat tab di bawah layar: Beranda, Operasional, Referensi, dan Profil. Operasional berisi pekerjaan harian, Referensi berisi data yang dicari saat dibutuhkan. Menu yang muncul mengikuti peran dan site akun Anda.',
      ),
      _GuideEntry(
        'Harus online',
        'SICATAT hanya bekerja saat ada internet. Bila data gagal dimuat, periksa koneksi lalu ketuk Muat ulang. Jangan menghapus aplikasi.',
      ),
    ],
  ),
  _GuideGroupData(
    title: 'Suhu',
    icon: Icons.thermostat_rounded,
    entries: <_GuideEntry>[
      _GuideEntry(
        'Membuat sheet',
        'Buka Operasional lalu Suhu, pilih Buat sheet, kemudian pilih tanggal inspeksi dan shift yang benar. Satu sheet hanya untuk satu kombinasi tanggal, shift, modul, dan site. Kombinasi yang sama akan ditolak.',
      ),
      _GuideEntry(
        'Ronde 1 dan Ronde 2',
        'Pilih unit serta sisi Barat atau Timur, lalu simpan setiap sisi. Waktu ronde tercatat otomatis saat data pertama disimpan. Sheet boleh tetap draf dan dilanjutkan sebelum shift berakhir.',
      ),
      _GuideEntry(
        'Kondisi unit',
        'Pilih Beroperasi untuk mengisi seluruh titik suhu. Bila unit Tidak beroperasi atau Tidak dapat diakses, isi alasannya dan titik suhu dikosongkan.',
      ),
      _GuideEntry(
        'Warna suhu',
        'Hijau di bawah 60 derajat C. Kuning 60 sampai 69 derajat C dan perlu perhatian. Merah 70 derajat C atau lebih, laporkan segera sesuai prosedur.',
      ),
      _GuideEntry(
        'Nilai tidak wajar',
        'Nilai di luar -50 sampai 250 derajat C harus dikonfirmasi dan diberi catatan. Catatan itu hanya menempel pada angka yang tidak wajar, bukan pada seluruh ronde.',
      ),
      _GuideEntry(
        'Ringkasan dan kirim',
        'Buka Ringkasan sheet untuk melihat bagian yang belum lengkap, lalu ketuk kartu merah untuk langsung membuka data yang kurang. Sheet yang sudah dikirim bersifat final; pembuatnya masih dapat membuka kembali untuk revisi, sedangkan sheet lama yang terverifikasi terkunci.',
      ),
    ],
  ),
  _GuideGroupData(
    title: 'Laporan dan ekspor',
    icon: Icons.description_outlined,
    entries: <_GuideEntry>[
      _GuideEntry(
        'Ekspor satu sheet',
        'Dari ringkasan sheet, pilih ikon ekspor untuk melihat pratinjau PDF atau mengunduh CSV. PDF memakai warna suhu; CSV tidak dapat berwarna sehingga memakai kolom Temperature Alert.',
      ),
      _GuideEntry(
        'Laporan periode',
        'Menu Laporan menggabungkan beberapa tanggal sekaligus. Pilih rentang tanggal dan regu, lalu ekspor PDF atau CSV. Judulnya menyebut jumlah sheet yang berisi data beserta jumlah barisnya.',
      ),
      _GuideEntry(
        'Suhu tinggi',
        'Menampilkan pembacaan 60 derajat C ke atas dari seluruh sheet, supaya yang berisiko ditangani lebih dulu.',
      ),
      _GuideEntry(
        'Sheet belum lengkap',
        'Daftar sheet yang masih punya isian kosong, agar tidak ada yang tertinggal di akhir shift.',
      ),
    ],
  ),
  _GuideGroupData(
    title: 'Pengingat',
    icon: Icons.notifications_none_rounded,
    entries: <_GuideEntry>[
      _GuideEntry(
        'Membuat pengingat',
        'Isi judul, kategori, aset, nomor dokumen, instansi, tindakan, penanggung jawab, lokasi, prioritas, dan tanggal berakhir. Pengingat adalah menu admin.',
      ),
      _GuideEntry(
        'Jadwal email',
        'Pilih mingguan, bulanan, atau jumlah hari sendiri sebelum jatuh tempo. Email dikirim tepat pada hari itu saja, bukan setiap hari, dan hanya untuk pengingat yang belum lewat jatuh tempo.',
      ),
      _GuideEntry(
        'Lampiran dokumen',
        'Lampirkan PDF, JPG, JPEG, atau PNG. Foto dikompres otomatis supaya hemat penyimpanan; PDF maksimal 2 MB, kecilkan dulu bila lebih besar.',
      ),
      _GuideEntry(
        'Menyelesaikan pengingat',
        'Ketuk Tandai selesai, isi catatan bila perlu, lalu unggah minimal satu bukti. Gunakan Buka kembali bila pekerjaan ternyata belum tuntas.',
      ),
      _GuideEntry(
        'Pengingat berulang',
        'Bila pengingat diatur berulang, siklus berikutnya dibuat otomatis setelah yang sekarang ditandai selesai.',
      ),
      _GuideEntry(
        'Peringatan email',
        'Server memeriksa izin pengiriman email setiap hari. Bila kotak merah muncul di layar Pengingat, email tidak akan terkirim sampai izin Gmail diperbarui admin.',
      ),
    ],
  ),
  _GuideGroupData(
    title: 'Notulen rapat',
    icon: Icons.groups_outlined,
    entries: <_GuideEntry>[
      _GuideEntry(
        'Membuat notulen',
        'Isi judul, tanggal, jam, lokasi, peserta, dan pembahasan. Notulen dapat disimpan sebagai draf dulu sebelum dilengkapi.',
      ),
      _GuideEntry(
        'Rencana tindakan',
        'Tambahkan rencana tindakan beserta penanggung jawab dan tenggatnya. Setiap rencana dapat diberi maksimal dua foto, dan fotonya dikompres otomatis sebelum diunggah.',
      ),
      _GuideEntry(
        'Tindak lanjut',
        'Gunakan Tindak lanjut untuk membuat notulen lanjutan yang membawa rencana tindakan yang belum selesai.',
      ),
      _GuideEntry(
        'Ekspor Excel',
        'Ikon di kanan atas mengunduh notulen dalam format Excel, lengkap dengan foto rencana tindakan.',
      ),
    ],
  ),
  _GuideGroupData(
    title: 'Anggaran dan pekerjaan',
    icon: Icons.account_balance_wallet_outlined,
    entries: <_GuideEntry>[
      _GuideEntry(
        'Anggaran Operasional',
        'Menampilkan anggaran dan realisasi per elemen biaya beserta sisanya. Angkanya mengikuti spreadsheet sumber dan hanya dapat dibaca.',
      ),
      _GuideEntry(
        'Outstanding PM & CM',
        'Daftar pekerjaan preventif dan korektif yang belum selesai, dipisah per unit dan site.',
      ),
      _GuideEntry(
        'Data PR',
        'Cari Purchase Requisition dan PO berdasarkan nomor atau uraian. Urutan No. PR terbaru memakai angka, bukan abjad. Bila hasilnya lebih dari 60 baris, daftar diakhiri catatan supaya kata kunci dipersempit.',
      ),
      _GuideEntry(
        'Permintaan Barang',
        'Mengajukan kebutuhan barang untuk LV dan Drilling. Permintaan yang sudah dibuat tidak dapat dihapus, jadi periksa dulu sebelum menyimpan.',
      ),
    ],
  ),
  _GuideGroupData(
    title: 'Gudang',
    icon: Icons.inventory_2_outlined,
    entries: <_GuideEntry>[
      _GuideEntry(
        'Mencari stok',
        'Ketik minimal dua karakter untuk mencari nama item, kode SC, atau lokasi bin. Daftar memang kosong sebelum ada pencarian.',
      ),
      _GuideEntry(
        'Melihat detail',
        'Ketuk kartu item untuk melihat kode SC, site, lokasi bin, satuan, stok, harga unit, serta tanggal pembaruan spreadsheet.',
      ),
      _GuideEntry(
        'Stok dan alat',
        'Tab Stok & harga untuk barang, tab Alat untuk peralatan. Filter site mempersempit hasil.',
      ),
      _GuideEntry(
        'Hasil terlalu banyak',
        'Hanya 100 item pertama yang ditampilkan. Bila catatan itu muncul di akhir daftar, persempit kata kunci atau pilih gudang tertentu.',
      ),
    ],
  ),
  _GuideGroupData(
    title: 'Pusat Dokumen dan referensi',
    icon: Icons.folder_open_outlined,
    entries: <_GuideEntry>[
      _GuideEntry(
        'Bertanya ke Pusat Dokumen',
        'Tulis pertanyaan memakai kata yang dipakai di dokumen, misalnya nama pekerjaan, nomor SOP, atau nama unit. Jawaban hanya diambil dari berkas di folder dokumen, bukan dari internet.',
      ),
      _GuideEntry(
        'Membaca jawaban',
        'Di bawah jawaban selalu ada daftar sumber. Buka berkas aslinya sebelum dipakai sebagai dasar pekerjaan. Jawaban biasanya butuh 10 sampai 25 detik karena dokumennya dibaca lebih dulu.',
      ),
      _GuideEntry(
        'Cost Code',
        'Mencari struktur dan elemen biaya beserta referensinya.',
      ),
      _GuideEntry(
        'Equipment Reference',
        'Mencari data unit Asamasam dan Kintap.',
      ),
    ],
  ),
  _GuideGroupData(
    title: 'Profil dan aplikasi',
    icon: Icons.person_outline_rounded,
    entries: <_GuideEntry>[
      _GuideEntry(
        'Ganti password',
        'Buka Profil lalu Ganti password. Password baru minimal delapan karakter, gabungan huruf dan angka. Setelah berhasil, semua perangkat lain ikut keluar dan harus masuk lagi.',
      ),
      _GuideEntry(
        'Memperbarui Android',
        'Buka Profil, pilih Pembaruan aplikasi, ketuk Periksa pembaruan, lalu Unduh dan pasang bila tersedia. Izinkan pemasangan saat Android meminta. Tidak perlu menghapus aplikasi lama.',
      ),
      _GuideEntry(
        'Versi web',
        'Versi web tidak perlu diperbarui manual. Bila tampilan terasa tertinggal, muat ulang halaman.',
      ),
    ],
  ),
  _GuideGroupData(
    title: 'Untuk admin',
    icon: Icons.admin_panel_settings_outlined,
    entries: <_GuideEntry>[
      _GuideEntry(
        'Data master',
        'Kelola site, shift, regu, rotasi regu, peralatan, titik ukur, dan template formulir. Data master tidak dapat dihapus, hanya dinonaktifkan, supaya riwayat lama tetap terbaca.',
      ),
      _GuideEntry(
        'Batas suhu',
        'Atur batas peringatan dan alarm per titik ukur. Angkanya wajib valid, batas peringatan harus lebih kecil dari alarm, dan sumber acuan wajib diisi.',
      ),
      _GuideEntry(
        'Pengguna',
        'Tambah pengguna baru lewat Data master & pengguna. Pembuatan akun membutuhkan PIN awal dan hanya dapat dilakukan admin aktif.',
      ),
    ],
  ),
];

class CrewGuideScreen extends StatelessWidget {
  const CrewGuideScreen({super.key});

  Future<void> _downloadIndonesianPdf() async {
    final pw.Document document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(42),
        build: (_) => <pw.Widget>[
          pw.Text(
            'Panduan pengguna SICATAT',
            style: const pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Disusun per menu aplikasi, mengikuti urutan pada layar Panduan pengguna.',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 18),
          ..._guideGroups.expand(
            (_GuideGroupData group) => <pw.Widget>[
              pw.Text(
                group.title,
                style: const pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              ...group.entries.expand(
                (_GuideEntry entry) => <pw.Widget>[
                  pw.Text(
                    entry.title,
                    style: const pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    entry.description,
                    style: const pw.TextStyle(fontSize: 10.5),
                  ),
                  pw.SizedBox(height: 8),
                ],
              ),
              pw.SizedBox(height: 8),
            ],
          ),
        ],
      ),
    );
    final Uint8List bytes = await document.save();
    await Printing.sharePdf(bytes: bytes, filename: 'Panduan-SICATAT.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/dashboard'),
          title: const Text(
            'Panduan pengguna SICATAT',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Card(
              color: AppColors.mint,
              child: ListTile(
                leading: const Icon(
                  Icons.picture_as_pdf_outlined,
                  color: AppColors.green,
                ),
                title: const Text('Unduh PDF Bahasa Indonesia'),
                subtitle: const Text(
                  'Simpan panduan untuk dibaca tanpa membuka aplikasi',
                ),
                trailing: const Icon(Icons.download_rounded),
                onTap: _downloadIndonesianPdf,
              ),
            ),
            const SizedBox(height: 12),
            for (final _GuideGroupData group in _guideGroups)
              _GuideGroup(
                group: group,
                initiallyExpanded: identical(group, _guideGroups.first),
              ),
          ],
        ),
      ),
    );
  }
}

class _GuideGroup extends StatelessWidget {
  const _GuideGroup({required this.group, this.initiallyExpanded = false});

  final _GuideGroupData group;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      leading: CircleAvatar(
        backgroundColor: AppColors.mint,
        child: Icon(group.icon, color: AppColors.green),
      ),
      title: Text(
        group.title,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        '${group.entries.length} panduan',
        style: const TextStyle(color: AppColors.muted, fontSize: 12),
      ),
      children: <Widget>[
        const Divider(height: 1),
        for (final _GuideEntry entry in group.entries)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.title,
                  style: const TextStyle(
                    color: AppColors.greenDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.description,
                  style: const TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
      ],
    ),
  );
}
