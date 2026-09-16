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

  test('a link may be pasted without its scheme', () {
    const String expected = 'https://www.tokopedia.com/search?q=filter';
    expect(
      MaterialRequestProductLink.normalize('www.tokopedia.com/search?q=filter'),
      expected,
    );
    expect(
      MaterialRequestProductLink.normalize(
        '  www.tokopedia.com/search?q=filter ',
      ),
      expected,
    );
    expect(
      MaterialRequestProductLink.normalize('tokopedia.com/p/1'),
      'https://tokopedia.com/p/1',
    );
    // An address that already carries a scheme is kept as typed.
    expect(
      MaterialRequestProductLink.normalize('http://toko.local/p/1'),
      'http://toko.local/p/1',
    );
    expect(
      MaterialRequestProductLink.normalize('https://toko.local/p/1'),
      'https://toko.local/p/1',
    );
    expect(MaterialRequestProductLink.normalize('   '), isNull);
    expect(MaterialRequestProductLink.normalize(null), isNull);
  });

  test('a bare word or a broken address is refused', () {
    for (final String value in <String>[
      'kacamata',
      'www',
      'ftp://toko.com/p',
      'https://toko com/p',
    ]) {
      expect(
        MaterialRequestProductLink.normalize(value),
        isNull,
        reason: value,
      );
      expect(
        MaterialRequestProductLink.validate(value),
        MaterialRequestProductLink.invalidMessage,
        reason: value,
      );
    }
    expect(MaterialRequestProductLink.validate('www.toko.com/p'), isNull);
    expect(MaterialRequestProductLink.validate(''), isNull);
  });

  test('a request carries its optional photo', () {
    MaterialRequest parse(Object? path, Object? mime) =>
        MaterialRequest.fromJson(<String, Object?>{
          'id': 'a',
          'request_area': 'lv',
          'item_name': 'Filter oli',
          'quantity': 1,
          'unit': 'pcs',
          'need_type': 'repair',
          'reason': 'rusak',
          'photo_path': path,
          'photo_mime': mime,
          'status': 'submitted',
          'requested_by': 'b',
          'created_at': '2026-09-16T00:00:00Z',
        });

    expect(parse('user/1-foto.jpg', 'image/jpeg').photoPath, 'user/1-foto.jpg');
    expect(parse('user/1-foto.jpg', 'image/jpeg').photoMime, 'image/jpeg');
    expect(parse(null, null).photoPath, isNull);
    expect(parse('  ', null).photoPath, isNull);
  });
}
