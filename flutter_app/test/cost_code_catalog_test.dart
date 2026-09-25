import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/features/documents/data/cost_code_catalog.dart';

void main() {
  test('katalog cost code memuat semua kode dari manual PDF', () {
    int count(String segment) =>
        costCodeCatalog.where((entry) => entry.segment == segment).length;
    // Cost Code User Guide Revisi 01, pages 4-19.
    expect(count('Site'), 14);
    expect(count('Function'), 35);
    expect(count('Pit/Plant'), 88);
    expect(count('Activity'), 56);
    expect(count('Expense'), 363);

    final Set<String> keys = <String>{
      for (final CostCodeEntry entry in costCodeCatalog)
        '${entry.segment}|${entry.code}',
    };
    expect(keys.length, costCodeCatalog.length);

    CostCodeEntry find(String segment, String code) => costCodeCatalog
        .firstWhere((entry) => entry.segment == segment && entry.code == code);
    expect(find('Site', '21').description, 'Satui');
    expect(find('Function', '90').description, 'Repair & Maintenance');
    expect(find('Pit/Plant', 'A001').site, 'Asam Asam');
    expect(find('Activity', '314').group, 'Barging to NPLCT');
    expect(find('Expense', '00396').group, 'Maintenance cost');
    expect(find('Expense', '00396').matches('tools'), isTrue);
  });
}
