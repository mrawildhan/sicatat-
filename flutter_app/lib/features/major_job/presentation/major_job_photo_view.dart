import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../major_job_api.dart';
import '../major_job_models.dart';
import '../major_job_pdf.dart';

/// Shows a photo cropped exactly as the PDF crops it (5.4 × 3.6 cm landscape,
/// 2.4 × 3.6 cm portrait), so what the owner sees here is what gets printed.
class MajorJobPhotoView extends StatefulWidget {
  const MajorJobPhotoView({
    required this.api,
    required this.photo,
    required this.height,
    this.bytes,
    this.onTap,
    super.key,
  });

  final MajorJobApi api;
  final MajorJobPhoto photo;
  final double height;

  /// Local bytes of a photo that is not uploaded yet; the server is not asked.
  final Uint8List? bytes;

  /// Opens the photo large, e.g. with [showMajorJobPhotoViewer].
  final VoidCallback? onTap;

  static double widthFor(MajorJobPhoto photo, double height) =>
      height *
      (photo.isLandscape ? majorJobLandscapeWidthCm : majorJobPortraitWidthCm) /
      majorJobPhotoHeightCm;

  @override
  State<MajorJobPhotoView> createState() => _MajorJobPhotoViewState();
}

class _MajorJobPhotoViewState extends State<MajorJobPhotoView> {
  late Future<Uint8List> _bytes = _load();

  Future<Uint8List> _load() => widget.bytes != null
      ? Future<Uint8List>.value(widget.bytes)
      : widget.api.photoBytes(widget.photo.id);

  @override
  void didUpdateWidget(MajorJobPhotoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.id != widget.photo.id ||
        !identical(oldWidget.bytes, widget.bytes)) {
      _bytes = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget image = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: MajorJobPhotoView.widthFor(widget.photo, widget.height),
        height: widget.height,
        child: FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, snapshot) {
            final Uint8List? bytes = snapshot.data;
            if (bytes != null) {
              return Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              );
            }
            return ColoredBox(
              color: AppColors.mint,
              child: Center(
                child: snapshot.hasError
                    ? const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.muted,
                      )
                    : const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
            );
          },
        ),
      ),
    );
    if (widget.onTap == null) return image;
    return Semantics(
      button: true,
      label: 'Perbesar foto',
      child: MouseRegion(
        cursor: SystemMouseCursors.zoomIn,
        child: GestureDetector(onTap: widget.onTap, child: image),
      ),
    );
  }
}

/// Opens [photos] full screen, uncropped, starting at [initialIndex]. Swipe
/// or use the arrows to move between photos; pinch or scroll to zoom.
Future<void> showMajorJobPhotoViewer(
  BuildContext context, {
  required List<Future<Uint8List> Function()> photos,
  int initialIndex = 0,
}) => showDialog<void>(
  context: context,
  barrierColor: Colors.black,
  builder: (_) =>
      _MajorJobPhotoViewer(photos: photos, initialIndex: initialIndex),
);

class _MajorJobPhotoViewer extends StatefulWidget {
  const _MajorJobPhotoViewer({
    required this.photos,
    required this.initialIndex,
  });

  final List<Future<Uint8List> Function()> photos;
  final int initialIndex;

  @override
  State<_MajorJobPhotoViewer> createState() => _MajorJobPhotoViewerState();
}

class _MajorJobPhotoViewerState extends State<_MajorJobPhotoViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  late final List<Future<Uint8List>?> _loaded = List<Future<Uint8List>?>.filled(
    widget.photos.length,
    null,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<Uint8List> _photo(int index) =>
      _loaded[index] ??= widget.photos[index]();

  void _go(int delta) => _pages.animateToPage(
    _index + delta,
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOut,
  );

  @override
  Widget build(BuildContext context) {
    final int count = widget.photos.length;
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _pages,
            itemCount: count,
            onPageChanged: (int index) => setState(() => _index = index),
            itemBuilder: (_, int index) => FutureBuilder<Uint8List>(
              future: _photo(index),
              builder: (context, snapshot) {
                final Uint8List? bytes = snapshot.data;
                if (bytes == null) {
                  return Center(
                    child: snapshot.hasError
                        ? const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                            size: 48,
                          )
                        : const CircularProgressIndicator(color: Colors.white),
                  );
                }
                return InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Tutup',
                    color: Colors.white,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  const Spacer(),
                  if (count > 1)
                    Text(
                      '${_index + 1} / $count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
          if (count > 1) ...<Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Foto sebelumnya',
                color: Colors.white,
                iconSize: 36,
                onPressed: _index == 0 ? null : () => _go(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Foto berikutnya',
                color: Colors.white,
                iconSize: 36,
                onPressed: _index == count - 1 ? null : () => _go(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
