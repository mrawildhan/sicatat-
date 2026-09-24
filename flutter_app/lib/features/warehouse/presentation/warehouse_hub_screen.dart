import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_navigation.dart';
import '../../../core/widgets/menu_choice_card.dart';
import '../../../data/models/app_user.dart';
import '../../auth/application/current_user_provider.dart';

/// Gudang opens here first. Everyone may search stock and tools; warehouse
/// managers also see the transactions (owner request 2026-09-24).
class WarehouseHubScreen extends ConsumerWidget {
  const WarehouseHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool canManage =
        ref.watch(currentUserProvider)?.role.canManageWarehouse == true;
    final List<(IconData, String, String, String)> choices =
        <(IconData, String, String, String)>[
          (
            Icons.manage_search_rounded,
            'Cari barang',
            'Stok, harga, lokasi bin, dan daftar alat',
            '/warehouse/search',
          ),
          if (canManage) ...<(IconData, String, String, String)>[
            (
              Icons.outbox_outlined,
              'Pengambilan Barang',
              'Catat barang yang diambil dari gudang',
              '/warehouse/issues',
            ),
            (
              Icons.handyman_outlined,
              'Peminjaman Alat',
              'Pinjam, kembalikan, dan daftarkan alat',
              '/warehouse/tool-loans',
            ),
            (
              Icons.move_to_inbox_outlined,
              'Penerimaan Barang',
              'Terima barang per PO/DO dan cek PO / PR / stok',
              '/warehouse/receipts',
            ),
          ],
        ];
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(fallbackRoute: '/dashboard'),
          title: const Text(
            'Gudang',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: <Widget>[
            MenuChoiceList(
              cards: <MenuChoiceCard>[
                for (final (
                      IconData icon,
                      String title,
                      String subtitle,
                      String route,
                    )
                    in choices)
                  MenuChoiceCard(
                    icon: icon,
                    title: title,
                    subtitle: subtitle,
                    onTap: () => context.go(route),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
