import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_navigation.dart';

class BudgetOverviewScreen extends StatelessWidget {
  const BudgetOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) => const _OperationalSectionPage(
    title: 'Anggaran Operasional',
    icon: Icons.account_balance_wallet_rounded,
    child: _BudgetOverviewBody(),
  );
}

class MeetingMinutesScreen extends StatelessWidget {
  const MeetingMinutesScreen({super.key});

  @override
  Widget build(BuildContext context) => const _OperationalSectionPage(
    title: 'Notulen Rapat',
    icon: Icons.assignment_rounded,
    child: _MeetingMinutesBody(),
  );
}

class _OperationalSectionPage extends StatelessWidget {
  const _OperationalSectionPage({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final useDesktopHeader = kIsWeb && MediaQuery.sizeOf(context).width >= 920;
    return AppBackScope(
      fallbackRoute: '/dashboard',
      child: Scaffold(
        appBar: useDesktopHeader
            ? null
            : AppBar(
                leading: const AppBackButton(fallbackRoute: '/dashboard'),
                title: Text(title),
              ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            useDesktopHeader ? 18 : 20,
            20,
            120 + MediaQuery.paddingOf(context).bottom,
          ),
          children: <Widget>[
            if (useDesktopHeader) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, color: AppColors.green, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _BudgetOverviewBody extends StatelessWidget {
  const _BudgetOverviewBody();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const Text(
        'Cek sisa anggaran plant',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 6),
      const Text(
        'Pantau anggaran, aktual, dan sisa biaya operasional setiap bulan.',
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 18),
      const Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.mint,
            child: Icon(Icons.calendar_month_rounded, color: AppColors.green),
          ),
          title: Text('Periode anggaran'),
          subtitle: Text('Pilih periode setelah spreadsheet dihubungkan'),
          trailing: Icon(Icons.expand_more_rounded),
          onTap: null,
        ),
      ),
      const SizedBox(height: 14),
      LayoutBuilder(
        builder: (_, constraints) => _BudgetMetricLayout(constraints),
      ),
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.25)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.info_outline_rounded, color: AppColors.orange),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Data budget dan aktual belum dihubungkan. Setelah spreadsheet tersedia, halaman ini akan menampilkan sisa anggaran serta peringatan sebelum terjadi overbudget.',
                style: TextStyle(height: 1.45),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.table_chart_outlined, color: AppColors.green),
                  SizedBox(width: 10),
                  Text(
                    'Sumber data',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Text(
                'Spreadsheet budget dan aktual',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                'Belum dihubungkan',
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _BudgetMetricLayout extends StatelessWidget {
  const _BudgetMetricLayout(this.constraints);

  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    final double width = constraints.maxWidth >= 760
        ? (constraints.maxWidth - 24) / 3
        : (constraints.maxWidth - 10) / 2;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        _BudgetMetricCard(
          width: width,
          label: 'Anggaran',
          icon: Icons.account_balance_wallet_outlined,
          color: AppColors.green,
        ),
        _BudgetMetricCard(
          width: width,
          label: 'Aktual',
          icon: Icons.receipt_long_outlined,
          color: AppColors.orange,
        ),
        _BudgetMetricCard(
          width: width,
          label: 'Sisa anggaran',
          icon: Icons.savings_outlined,
          color: AppColors.greenDark,
        ),
      ],
    );
  }
}

class _BudgetMetricCard extends StatelessWidget {
  const _BudgetMetricCard({
    required this.width,
    required this.label,
    required this.icon,
    required this.color,
  });

  final double width;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(height: 16),
            Text(label, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 6),
            const Text(
              '—',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MeetingMinutesBody extends StatelessWidget {
  const _MeetingMinutesBody();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const Text(
        'Notulen inspeksi dan rapat lapangan',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 6),
      const Text(
        'Buat, simpan sebagai draf, lalu selesaikan notulen ketika informasi sudah lengkap.',
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 18),
      const Wrap(
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          _MeetingStatusChip(
            label: 'Draf',
            count: '0',
            color: AppColors.orange,
          ),
          _MeetingStatusChip(
            label: 'Selesai',
            count: '0',
            color: AppColors.green,
          ),
        ],
      ),
      const SizedBox(height: 18),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: <Widget>[
              const CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.mint,
                child: Icon(
                  Icons.edit_note_rounded,
                  color: AppColors.green,
                  size: 34,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Belum ada notulen',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'Format input MOM akan disesuaikan dari contoh yang Anda kirim. Draf dapat disimpan tanpa harus langsung diselesaikan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, height: 1.45),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Buat notulen'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      const Card(
        child: ListTile(
          leading: Icon(Icons.save_as_outlined, color: AppColors.green),
          title: Text('Alur kerja MOM'),
          subtitle: Text('Buat → Simpan draf → Lengkapi → Selesaikan'),
        ),
      ),
    ],
  );
}

class _MeetingStatusChip extends StatelessWidget {
  const _MeetingStatusChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final String count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      '$label  $count',
      style: TextStyle(color: color, fontWeight: FontWeight.w800),
    ),
  );
}
