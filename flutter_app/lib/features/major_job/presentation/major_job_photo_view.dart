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
    super.key,
  });

  final MajorJobApi api;
  final MajorJobPhoto photo;
  final double height;

  static double widthFor(MajorJobPhoto photo, double height) =>
      height *
      (photo.isLandscape ? majorJobLandscapeWidthCm : majorJobPortraitWidthCm) /
      majorJobPhotoHeightCm;

  @override
  State<MajorJobPhotoView> createState() => _MajorJobPhotoViewState();
}

class _MajorJobPhotoViewState extends State<MajorJobPhotoView> {
  late Future<Uint8List> _bytes = widget.api.photoBytes(widget.photo.id);

  @override
  void didUpdateWidget(MajorJobPhotoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.id != widget.photo.id) {
      _bytes = widget.api.photoBytes(widget.photo.id);
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(
      width: MajorJobPhotoView.widthFor(widget.photo, widget.height),
      height: widget.height,
      child: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          final Uint8List? bytes = snapshot.data;
          if (bytes != null) {
            return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
          }
          return ColoredBox(
            color: AppColors.mint,
            child: Center(
              child: snapshot.hasError
                  ? const Icon(Icons.broken_image_outlined, color: AppColors.muted)
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
}
