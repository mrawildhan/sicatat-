import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';
import '../guide_content.dart';

/// Icon per group. The content itself lives in `guide_content.dart`, which
/// stays free of Flutter so the same text can be rendered to PDF by
/// `tool/generate_guide_pdf.dart`.
const Map<String, IconData> _groupIcons = <String, IconData>{
  'Dasar penggunaan': Icons.play_circle_outline_rounded,
  'Suhu': Icons.thermostat_rounded,
  'Laporan dan ekspor': Icons.description_outlined,
  'Pengingat': Icons.notifications_none_rounded,
  'Notulen rapat': Icons.groups_outlined,
  'Anggaran dan pekerjaan': Icons.account_balance_wallet_outlined,
  'Gudang': Icons.inventory_2_outlined,
  'Pusat Dokumen dan referensi': Icons.folder_open_outlined,
  'Profil dan aplikasi': Icons.person_outline_rounded,
  'Untuk admin': Icons.admin_panel_settings_outlined,
};

class CrewGuideScreen extends StatelessWidget {
  const CrewGuideScreen({super.key});

  Future<void> _downloadIndonesianPdf() async {
    final Uint8List bytes = await buildGuidePdfBytes();
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
            for (final GuideGroupContent group in guideGroups)
              _GuideGroup(
                group: group,
                initiallyExpanded: identical(group, guideGroups.first),
              ),
          ],
        ),
      ),
    );
  }
}

class _GuideGroup extends StatelessWidget {
  const _GuideGroup({required this.group, this.initiallyExpanded = false});

  final GuideGroupContent group;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      leading: CircleAvatar(
        backgroundColor: AppColors.mint,
        child: Icon(
          _groupIcons[group.title] ?? Icons.menu_book_outlined,
          color: AppColors.green,
        ),
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
        for (final GuideEntry entry in group.entries)
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
