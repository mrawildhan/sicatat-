import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/features/warehouse/warehouse_data.dart';

void main() {
  test('kode SC Ellipse dan lembar kerja disamakan', () {
    expect(normalizeStockCode('000004675'), '4675');
    expect(normalizeStockCode(' 0205 '), '205');
    expect(normalizeStockCode('0'), '0');
    expect(normalizeStockCode('st54318'), 'ST54318');
  });

  test('PO outstanding: jasa dan lewat jatuh tempo', () {
    final WarehouseOutstandingPo service = WarehouseOutstandingPo.fromJson(
      <String, Object?>{
        'po_no': 'P53166',
        'qty_order': 0,
        'qty_outstanding': 0,
        'due_date': '2026-09-20',
      },
    );
    expect(service.isService, isTrue);
    expect(service.isOverdue(DateTime(2026, 9, 24)), isTrue);
    expect(service.isOverdue(DateTime(2026, 9, 20)), isFalse);

    final WarehouseOutstandingPo goods = WarehouseOutstandingPo.fromJson(
      <String, Object?>{
        'po_no': 'P53106',
        'item_code': '2908',
        'description': 'LED FLOOD LIGHT',
        'supplier_name': 'BORNEO MAJUJAYA PT',
        'qty_order': 6,
        'qty_outstanding': 6,
      },
    );
    expect(goods.isService, isFalse);
    expect(goods.isOverdue(DateTime(2026, 9, 24)), isFalse);
    expect(goods.searchText, contains('borneo'));
    // Stock-coded lines have no requestor: they are warehouse restock.
    expect(goods.orderedFor, 'Stok gudang');
    expect(goods.searchText, contains('stok gudang'));

    final WarehouseOutstandingPo requested = WarehouseOutstandingPo.fromJson(
      <String, Object?>{'po_no': 'P50458', 'requestor': 'Citra Mulia Setiawan'},
    );
    expect(requested.orderedFor, 'Citra Mulia Setiawan');
    expect(requested.searchText, contains('citra'));
  });
}
