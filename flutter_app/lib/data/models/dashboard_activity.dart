/// Local activity summary used by the home dashboard.
///
/// Values are calculated from the on-device database so the dashboard remains
/// truthful even while the device is offline.
class DashboardActivity {
  const DashboardActivity({
    required this.draftCount,
    required this.syncedCount,
    required this.highTemperatureCount,
    required this.pendingSyncCount,
    required this.conflictCount,
  });

  final int draftCount;
  final int syncedCount;
  final int highTemperatureCount;
  final int pendingSyncCount;
  final int conflictCount;
}
