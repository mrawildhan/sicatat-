# Buku Panduan SICATAT

## Tujuan aplikasi

SICATAT digunakan untuk pencatatan temperature per shift dan pengelolaan reminder operasional. Aplikasi bekerja **online-only**; data yang disimpan selalu dikirim ke server Supabase.

## Memulai pencatatan temperature

1. Masuk menggunakan Crew ID/NIK dan PIN.
2. Buka tab **Temperature** lalu pilih **New sheet**.
3. Tentukan tanggal pemeriksaan dan shift. Shift Pagi berlangsung 07.00–19.00, sedangkan Shift Malam 19.00–07.00.
4. Isi Round 1 dan Round 2. Waktu setiap round direkam otomatis saat entri pertama disimpan; waktu tidak diisi manual.
5. Pilih status unit: **Operating**, **Not operating**, atau **Not accessible**. Status selain Operating harus disertai alasan.
6. Data boleh belum lengkap dan disimpan sebagai draft. Buka **Sheet summary** untuk melihat bagian yang lengkap maupun yang belum terisi. Tekan kartu merah untuk langsung menuju bagian yang kurang.
7. Setelah siap, pilih **Submit**. Sheet yang sudah diverifikasi terkunci; revisi dilakukan melalui alur Return/revision oleh petugas pemeriksa.

## Batas keselamatan temperature

| Nilai | Penanda | Tindakan |
| --- | --- | --- |
| Di bawah 60°C | Hijau | Pantau normal. |
| 60–69°C | Oranye | Perlu perhatian dan tindak lanjut sesuai prosedur. |
| 70°C atau lebih | Merah | Laporkan segera mengikuti prosedur operasi. |

Nilai di luar -50 sampai 250°C memerlukan konfirmasi anomali dan catatan sebelum dapat disimpan.

## Reminder operasional

1. Buka tab **Reminders** jika menu tersedia pada akun Anda.
2. Pilih **Add reminder** dan isi judul, site, tindakan yang diperlukan, PIC, prioritas, tanggal jatuh tempo, serta penerima email.
3. Centang jadwal email H-30, H-14, H-7, H-1, dan/atau hari jatuh tempo. Email otomatis dikirim pukul 08.00 WITA pada hari yang dipilih.
4. Tombol **Send email now** digunakan untuk mengirim pengingat manual.
5. Pilih **Mark complete** saat pekerjaan selesai. Untuk reminder berulang, sistem membuat reminder berikutnya sesuai periode yang dipilih. Gunakan **Reopen** jika pekerjaan perlu dibuka kembali.

## Hak akses

| Peran | Temperature | Reminder | Administrasi |
| --- | --- | --- | --- |
| Admin | Semua site; input, cek, verifikasi | Semua site | Semua, termasuk tambah pengguna |
| Supervisor SMG | Semua site; input, cek, verifikasi | Semua site | Semua master data, tanpa tambah pengguna |
| Supervisor COP | Melihat dan memeriksa seluruh team pada site penugasan | Tidak ada | Tidak ada |
| Foreman A/B/C | Melihat dan memeriksa crew pada team yang sama | Tidak ada | Tidak ada |
| Crew | Membuat dan mengisi sheet milik sendiri | Tidak ada | Tidak ada |
| Foreman LV | Tidak ada | Reminder pada site penugasan | Tidak ada |

## Multi-site

Setiap team, roster, sheet, dan reminder memiliki site. Saat ini tersedia **Asam-Asam** dan **Kintap**. Admin atau Supervisor SMG membuat site/team baru melalui Master data sebelum membuat akun untuk site tersebut.

## Jika ada kendala

- Tekan **Refresh** bila daftar data belum muncul.
- Pastikan koneksi internet aktif. Jangan menghapus aplikasi untuk mengatasi masalah koneksi.
- Gunakan tombol kembali di bagian atas aplikasi atau tombol kembali Android; aplikasi akan kembali ke halaman SICATAT, bukan keluar ke layar utama perangkat.
