import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:sicatat_flutter/features/major_job/major_job_api.dart';
import 'package:sicatat_flutter/features/major_job/major_job_models.dart';
import 'package:sicatat_flutter/features/major_job/presentation/major_job_editor_screen.dart';
import 'package:sicatat_flutter/features/major_job/presentation/major_job_photo_view.dart';

Uint8List _png(int width, int height) =>
    Uint8List.fromList(img.encodePng(img.Image(width: width, height: height)));

class _FakePicker extends FilePicker {
  _FakePicker(this.files);

  final List<PlatformFile> files;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult(files);
}

void main() {
  testWidgets('foto major job bisa diketuk lalu dibuka besar dan digeser', (
    tester,
  ) async {
    final Uint8List bytes = _png(3, 2);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => MajorJobPhotoView(
              api: MajorJobApi(accessToken: () async => null),
              photo: const MajorJobPhoto(
                id: 'lokal',
                position: 0,
                mimeType: 'image/png',
                width: 3,
                height: 2,
                sizeBytes: 0,
              ),
              bytes: bytes,
              height: 108,
              onTap: () => showMajorJobPhotoViewer(
                context,
                photos: <Future<Uint8List> Function()>[
                  () async => bytes,
                  () async => bytes,
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MajorJobPhotoView));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.byTooltip('Foto berikutnya'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets(
    'pekerjaan baru: foto dipilih sebelum simpan lalu diunggah bersama',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      FilePicker.platform = _FakePicker(<PlatformFile>[
        PlatformFile(name: 'lebar.png', size: 0, bytes: _png(6, 4)),
        PlatformFile(name: 'tegak.png', size: 0, bytes: _png(4, 6)),
      ]);
      final List<String> calls = <String>[];
      int uploaded = 0;
      final MockClient client = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.url.path == '/jobs') {
          final Map<String, Object?> body =
              jsonDecode(request.body) as Map<String, Object?>;
          expect(body['description'], 'Overhaul gearbox');
          return http.Response(
            jsonEncode(<String, Object?>{
              'job': <String, Object?>{
                'id': 'j1',
                'work_date': body['work_date'],
                'description': body['description'],
                'created_by': '1',
                'photos': <Object?>[],
              },
            }),
            201,
          );
        }
        uploaded++;
        return http.Response(
          jsonEncode(<String, Object?>{
            'photo': <String, Object?>{
              'id': 'p$uploaded',
              'position': uploaded,
              'mime_type': 'image/png',
              'width': 6,
              'height': 4,
              'size_bytes': request.bodyBytes.length,
            },
          }),
          201,
        );
      });
      final MajorJobApi api = MajorJobApi(
        client: client,
        baseUrl: 'https://api.test',
        accessToken: () async => 'token-uji',
      );
      final GoRouter router = GoRouter(
        initialLocation: '/major-job/new',
        routes: <RouteBase>[
          GoRoute(
            path: '/major-job',
            builder: (_, __) => const Scaffold(body: Text('DAFTAR')),
          ),
          GoRoute(
            path: '/major-job/new',
            builder: (_, __) => MajorJobEditorScreen(
              api: api,
              initialDate: DateTime(2026, 9, 24),
            ),
          ),
          GoRoute(
            path: '/major-job/job/:id',
            builder: (_, __) => const Scaffold(body: Text('HALAMAN JOB')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // Foto bisa ditambah sebelum pekerjaan disimpan.
      expect(find.text('Foto (0/8)'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Overhaul gearbox');
      await tester.tap(find.text('Tambah foto'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Foto (2/8)'), findsOneWidget);
      expect(find.text('Simpan pekerjaan & 2 foto'), findsOneWidget);
      expect(calls, isEmpty);

      await tester.tap(find.byType(MajorJobPhotoView).first);
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Simpan pekerjaan & 2 foto'));
      await tester.pumpAndSettle();
      expect(calls, <String>[
        'POST /jobs',
        'POST /jobs/j1/photos',
        'POST /jobs/j1/photos',
      ]);
      expect(find.text('DAFTAR'), findsOneWidget);
    },
  );
}
