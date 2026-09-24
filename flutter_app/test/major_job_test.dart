import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:sicatat_flutter/core/pdf/pdf_theme.dart';
import 'package:sicatat_flutter/data/reports/meeting_minute_photo_compressor.dart';
import 'package:sicatat_flutter/features/dashboard/presentation/grouped_bottom_navigation.dart';
import 'package:sicatat_flutter/features/major_job/major_job_api.dart';
import 'package:sicatat_flutter/features/major_job/major_job_models.dart';
import 'package:sicatat_flutter/features/major_job/major_job_pdf.dart';
import 'package:sicatat_flutter/features/major_job/presentation/major_job_screen.dart';

ByteData _font(String asset) =>
    ByteData.sublistView(File(asset).readAsBytesSync());

Uint8List _jpeg(int width, int height) => Uint8List.fromList(
  image.encodeJpg(image.Image(width: width, height: height), quality: 60),
);

MajorJobPhoto _photo(String id, int width, int height) => MajorJobPhoto(
  id: id,
  position: 1,
  mimeType: 'image/jpeg',
  width: width,
  height: height,
  sizeBytes: 1000,
);

MajorJob _job(String id, String date, List<MajorJobPhoto> photos) => MajorJob(
  id: id,
  workDate: DateTime.parse(date),
  description: 'Pekerjaan $id',
  createdBy: '123',
  photos: photos,
);

String _labels(List<MajorJobPeriod> periods) =>
    periods.map((p) => p.label).join(' | ');

void main() {
  test('periode laporan ditutup hari Senin dan tidak melewati akhir bulan', () {
    expect(
      _labels(majorJobPeriodsOfMonth(2026, 8)),
      '01 – 03 Agustus 2026 | 04 – 10 Agustus 2026 | 11 – 17 Agustus 2026 | '
      '18 – 24 Agustus 2026 | 25 – 31 Agustus 2026',
    );
    expect(
      _labels(majorJobPeriodsOfMonth(2026, 9)),
      '01 – 07 September 2026 | 08 – 14 September 2026 | '
      '15 – 21 September 2026 | 22 – 28 September 2026 | 29 – 30 September 2026',
    );
    // 1 June 2026 is itself a Monday: a one-day first period.
    expect(majorJobPeriodsOfMonth(2026, 6).first.label, '01 – 01 Juni 2026');
    expect(
      majorJobRangeLabel(DateTime(2026, 9, 28), DateTime(2026, 10, 4)),
      '28 September – 04 Oktober 2026',
    );
  });

  test('report mingguan kumulatif sejak tanggal 1, bulanan sebulan penuh', () {
    final List<MajorJob> jobs = <MajorJob>[
      _job('a', '2026-08-01', <MajorJobPhoto>[_photo('p1', 4, 3)]),
      _job('b', '2026-08-05', <MajorJobPhoto>[_photo('p2', 4, 3)]),
      _job('tanpa-foto', '2026-08-06', <MajorJobPhoto>[]),
      _job('c', '2026-08-12', <MajorJobPhoto>[_photo('p3', 3, 4)]),
    ];
    final MajorJobReport weekly = majorJobReportFor(
      kind: MajorJobReportKind.weekly,
      year: 2026,
      month: 8,
      jobs: jobs,
      until: majorJobPeriodsOfMonth(2026, 8)[1],
    );
    expect(weekly.fileName, 'Weekly Job 01 - 10 Agustus 2026.pdf');
    expect(weekly.sections.map((s) => s.period.label), <String>[
      '01 – 03 Agustus 2026',
      '04 – 10 Agustus 2026',
    ]);
    expect(weekly.jobs.map((j) => j.id), <String>['a', 'b']);

    final MajorJobReport monthly = majorJobReportFor(
      kind: MajorJobReportKind.monthly,
      year: 2026,
      month: 8,
      jobs: jobs,
    );
    expect(monthly.fileName, 'Mayor Job 01 - 31 Agustus 2026.pdf');
    expect(monthly.jobs.map((j) => j.id), <String>['a', 'b', 'c']);
  });

  test('foto disusun kiri ke kanan selama muat di kolom foto', () {
    const double cm = 72 / 2.54;
    List<int> rowSizes(List<double> widthsCm) => majorJobPhotoRows<double>(
      widthsCm.map((w) => w * cm).toList(),
      (w) => w,
    ).map((row) => row.length).toList();
    expect(rowSizes(<double>[5.4, 5.4, 5.4]), <int>[2, 1]);
    expect(rowSizes(<double>[2.4, 2.4, 2.4, 2.4]), <int>[4]);
    expect(rowSizes(<double>[5.4, 2.4, 2.4, 5.4]), <int>[3, 1]);
  });

  test('PDF memakai font aplikasi dan memuat setiap foto', () async {
    final MajorJobReport report = majorJobReportFor(
      kind: MajorJobReportKind.monthly,
      year: 2026,
      month: 8,
      jobs: <MajorJob>[
        _job('a', '2026-08-01', <MajorJobPhoto>[
          _photo('l1', 400, 300),
          _photo('p1', 300, 400),
          _photo('w1', 640, 360),
        ]),
        _job('b', '2026-08-20', <MajorJobPhoto>[_photo('l2', 400, 300)]),
      ],
    );
    final Uint8List bytes = await buildMajorJobPdf(
      report,
      photos: <String, Uint8List>{
        'l1': _jpeg(400, 300),
        'p1': _jpeg(300, 400),
        'w1': _jpeg(640, 360),
        'l2': _jpeg(400, 300),
      },
      theme: pdfThemeFromFontBytes(
        regular: _font(appFontRegularAsset),
        bold: _font(appFontBoldAsset),
      ),
    );
    final String raw = latin1.decode(bytes);
    final Set<String> fonts = RegExp(r'/BaseFont\s*/([A-Za-z0-9+\-_]+)')
        .allMatches(raw)
        .map((m) => m.group(1)!)
        .toSet();
    expect(fonts, isNotEmpty);
    expect(fonts.every((font) => font.contains('Roboto')), isTrue, reason: '$fonts');
    expect(RegExp(r'/Subtype\s*/Image').allMatches(raw).length, 4);
    // Each period starts on its own page, as in the Word reports.
    expect(RegExp(r'/Type\s*/Page\b').allMatches(raw).length, 2);
    final String? dir = Platform.environment['EXPORT_PDF_DIR'];
    if (dir != null) File('$dir/${report.fileName}').writeAsBytesSync(bytes);
  });

  test('kompresi Major Job mengikuti batas ukurannya sendiri', () {
    // Like a phone photo: a large, high-quality JPEG with some texture. (A
    // blank or smooth PNG is already smaller than any re-encode, and the
    // compressor rightly keeps such originals.)
    final image.Image photo = image.Image(width: 3000, height: 2000);
    for (final image.Pixel pixel in photo) {
      pixel
        ..r = pixel.x * 255 ~/ 3000
        ..g = pixel.y * 255 ~/ 2000
        ..b = (pixel.x * 7 + pixel.y * 13) % 256;
    }
    final Uint8List big = Uint8List.fromList(image.encodeJpg(photo, quality: 95));
    final CompressedMeetingMinutePhoto result =
        MeetingMinutePhotoCompressor.compress(
          bytes: big,
          fileName: 'foto.jpg',
          maxDimension: 1200,
          targetBytes: 200 * 1024,
        );
    final image.Image decoded = image.decodeImage(result.bytes)!;
    expect(decoded.width, lessThanOrEqualTo(1200));
    expect(decoded.width / decoded.height, closeTo(1.5, .01));
    expect(result.bytes.lengthInBytes, lessThanOrEqualTo(200 * 1024));
    // The Notulen defaults (1280 px / 600 KB) keep more; the limits apply.
    final CompressedMeetingMinutePhoto notulen =
        MeetingMinutePhotoCompressor.compress(bytes: big, fileName: 'foto.jpg');
    expect(result.bytes.lengthInBytes, lessThan(notulen.bytes.lengthInBytes));
  });

  testWidgets('menu Major Job hanya tampil untuk yang berhak', (tester) async {
    Future<void> openOperational({required bool canMajorJob}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: GroupedBottomNavigation(
              selected: 'home',
              canTemperature: true,
              canReminders: true,
              canWarehouse: true,
              canMajorJob: canMajorJob,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Operasional'));
      await tester.pumpAndSettle();
    }

    await openOperational(canMajorJob: false);
    expect(find.text('Major Job'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await openOperational(canMajorJob: true);
    expect(find.text('Major Job'), findsOneWidget);
  });

  testWidgets('pindah ?month= di halaman yang sama memuat ulang bulannya', (
    tester,
  ) async {
    final List<String> months = <String>[];
    final MockClient client = MockClient((request) async {
      if (request.url.path == '/usage') {
        return http.Response(
          '{"photos":0,"bytes":0,"capacity_bytes":1073741824}',
          200,
        );
      }
      final String month = request.url.queryParameters['month']!;
      months.add(month);
      return http.Response(
        jsonEncode(<String, Object?>{
          'jobs': <Object?>[
            <String, Object?>{
              'id': 'j-$month',
              'work_date': '$month-02',
              'description': 'Pekerjaan bulan $month',
              'created_by': '1',
              'photos': <Object?>[],
            },
          ],
        }),
        200,
      );
    });
    final MajorJobApi api = MajorJobApi(
      client: client,
      baseUrl: 'https://api.test',
      accessToken: () async => 'token-uji',
    );
    final GoRouter router = GoRouter(
      initialLocation: '/major-job?month=2026-08',
      routes: <RouteBase>[
        GoRoute(
          path: '/major-job',
          builder: (_, state) => MajorJobScreen(
            initialMonth: state.uri.queryParameters['month'],
            api: api,
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Pekerjaan bulan 2026-08'), findsOneWidget);

    router.go('/major-job?month=2026-09');
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('Pekerjaan bulan 2026-09'), findsOneWidget);
    expect(find.text('Pekerjaan bulan 2026-08'), findsNothing);
    expect(months, <String>['2026-08', '2026-09']);
  });

  testWidgets('daftar Major Job dikelompokkan per periode dengan nomor bersambung', (
    tester,
  ) async {
    final List<String> requests = <String>[];
    final MockClient client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}?${request.url.query}');
      expect(request.headers['authorization'], 'Bearer token-uji');
      if (request.url.path == '/jobs') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'jobs': <Object?>[
              <String, Object?>{
                'id': 'j1',
                'work_date': '2026-08-03',
                'description': 'Repainting demarkasi lantai warehouse',
                'created_by': '1',
                'photos': <Object?>[],
              },
              <String, Object?>{
                'id': 'j2',
                'work_date': '2026-08-04',
                'description': 'Fabrikasi lower chute sizer to CV12',
                'created_by': '1',
                'photos': <Object?>[],
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/usage') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'photos': 0,
            'bytes': 0,
            'capacity_bytes': 1073741824,
          }),
          200,
        );
      }
      return http.Response('{"error":"tidak ada"}', 404);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MajorJobScreen(
          initialMonth: '2026-08',
          api: MajorJobApi(
            client: client,
            baseUrl: 'https://api.test',
            accessToken: () async => 'token-uji',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests.first, 'GET /jobs?month=2026-08');
    expect(find.text('Agustus 2026'), findsOneWidget);
    expect(find.text('01 – 03 Agustus 2026'), findsOneWidget);
    expect(find.text('04 – 10 Agustus 2026'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'nomor bersambung antar periode');
    expect(find.text('Belum ada foto, tidak ikut di PDF'), findsNWidgets(2));
    expect(find.textContaining('Penyimpanan foto 0,0 MB dari 1,0 GB'), findsOneWidget);
  });
}
