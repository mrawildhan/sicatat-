import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/data/models/material_request_models.dart';

void main() {
  test('COP is a stored work area alongside LV and Drilling', () {
    expect(
      MaterialRequestArea.values.map(
        (MaterialRequestArea area) => area.storageValue,
      ),
      <String>['lv', 'cop', 'drilling'],
    );
    expect(MaterialRequestArea.cop.label, 'COP');
    expect(MaterialRequestAreaX.fromStorage('cop'), MaterialRequestArea.cop);
    expect(
      MaterialRequestAreaX.fromStorage('drilling'),
      MaterialRequestArea.drilling,
    );
    // Anything unknown must stay on the original default rather than throw.
    expect(MaterialRequestAreaX.fromStorage('mystery'), MaterialRequestArea.lv);
  });

  test('a request keeps its product link and treats blanks as absent', () {
    MaterialRequest parse(Object? url) =>
        MaterialRequest.fromJson(<String, Object?>{
          'id': 'a',
          'request_area': 'cop',
          'item_name': 'Filter oli',
          'quantity': 2,
          'unit': 'pcs',
          'need_type': 'replacement',
          'reason': 'rusak',
          'product_url': url,
          'status': 'submitted',
          'requested_by': 'b',
          'created_at': '2026-09-16T00:00:00Z',
        });

    expect(
      parse('https://toko.example/filter').productUrl,
      'https://toko.example/filter',
    );
    expect(
      parse('  https://toko.example/filter  ').productUrl,
      'https://toko.example/filter',
    );
    expect(parse('   ').productUrl, isNull);
    expect(parse(null).productUrl, isNull);
    expect(parse(null).area, MaterialRequestArea.cop);
  });
}
