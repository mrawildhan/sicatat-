import 'package:flutter_test/flutter_test.dart';
import 'package:sicatat_flutter/data/version/app_version_service.dart';

void main() {
  test('compares semantic application versions', () {
    expect(AppVersionService.compare('2.0.0', '2.0.0'), 0);
    expect(AppVersionService.compare('2.0.0', '2.0.1'), lessThan(0));
    expect(AppVersionService.compare('2.10.0', '2.9.9'), greaterThan(0));
    expect(AppVersionService.compare('2.0', '2.0.0'), 0);
  });
}
