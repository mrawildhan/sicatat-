import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/data/models/purchase_requisition_models.dart';

void main() {
  test('status Data PR: terakhir diperiksa, terakhir berubah, gagal', () {
    final DateTime changed = DateTime.utc(2026, 9, 24, 6, 27);
    final PurchaseRequisitionSnapshot ok = PurchaseRequisitionSnapshot.fromLog(
      <Map<String, Object?>>[
        <String, Object?>{
          'status': 'completed',
          'snapshot_rows': 2984,
          'completed_at': '2026-09-24T08:00:00Z',
        },
        <String, Object?>{
          'status': 'completed',
          'snapshot_rows': 2984,
          'completed_at': '2026-09-24T06:27:00Z',
        },
      ],
      changedAt: changed,
    )!;
    expect(ok.rows, 2984);
    expect(ok.checkedAt, DateTime.utc(2026, 9, 24, 8).toLocal());
    expect(ok.changedAt, changed.toLocal());
    expect(ok.lastError, isNull);

    final PurchaseRequisitionSnapshot failed =
        PurchaseRequisitionSnapshot.fromLog(<Map<String, Object?>>[
          <String, Object?>{
            'status': 'failed',
            'detail': 'File PR tidak dapat dibaca (HTTP 404).',
            'completed_at': '2026-09-24T09:00:00Z',
          },
          <String, Object?>{
            'status': 'completed',
            'snapshot_rows': 2984,
            'completed_at': '2026-09-24T08:00:00Z',
          },
        ], changedAt: changed)!;
    expect(failed.lastError, 'File PR tidak dapat dibaca (HTTP 404).');
    expect(failed.checkedAt, DateTime.utc(2026, 9, 24, 8).toLocal());

    expect(
      PurchaseRequisitionSnapshot.fromLog(<Map<String, Object?>>[
        <String, Object?>{'status': 'failed', 'completed_at': '2026-09-24'},
      ], changedAt: null),
      isNull,
    );
  });
}
