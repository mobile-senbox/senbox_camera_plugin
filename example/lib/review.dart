import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.imageFile, this.captureDebugInfo});

  final XFile imageFile;
  final Map<String, dynamic>? captureDebugInfo;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final Future<_ReviewData> _reviewFuture = _loadReviewData();

  Future<_ReviewData> _loadReviewData() async {
    final Uint8List fileBytes = await widget.imageFile.readAsBytes();
    final img.Image? decodedImage = img.decodeImage(fileBytes);

    if (decodedImage == null) {
      throw StateError('Unable to decode captured image.');
    }

    final bool hasExifOrientation = decodedImage.exif.imageIfd.hasOrientation;
    final int exifOrientation = decodedImage.exif.imageIfd.orientation ?? 1;

    final img.Image rawPreviewImage = img.Image.from(decodedImage)
      ..exif = img.ExifData();
    final img.Image bakedPreviewImage = img.bakeOrientation(decodedImage);

    return _ReviewData(
      filePath: widget.imageFile.path,
      fileSizeBytes: fileBytes.length,
      rawWidth: decodedImage.width,
      rawHeight: decodedImage.height,
      bakedWidth: bakedPreviewImage.width,
      bakedHeight: bakedPreviewImage.height,
      hasExifOrientation: hasExifOrientation,
      exifOrientation: exifOrientation,
      rawPreviewBytes: Uint8List.fromList(img.encodeJpg(rawPreviewImage)),
      bakedPreviewBytes: Uint8List.fromList(img.encodeJpg(bakedPreviewImage)),
      captureDebugInfo: widget.captureDebugInfo,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1016),
      appBar: AppBar(
        title: const Text('Captured Image Review'),
        backgroundColor: const Color(0xFF111926),
      ),
      body: FutureBuilder<_ReviewData>(
        future: _reviewFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load review data.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            );
          }

          final _ReviewData review = snapshot.requireData;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionCard(
                title: 'EXIF Summary',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoLine(
                      label: 'Orientation tag',
                      value: review.hasExifOrientation
                          ? '${review.exifOrientation} (${_orientationLabel(review.exifOrientation)})'
                          : 'Missing',
                    ),
                    _InfoLine(
                      label: 'Preview transform',
                      value: review.previewTransformLabel,
                    ),
                    _InfoLine(
                      label: 'Raw pixels',
                      value: '${review.rawWidth} x ${review.rawHeight}',
                    ),
                    _InfoLine(
                      label: 'Baked pixels',
                      value: '${review.bakedWidth} x ${review.bakedHeight}',
                    ),
                    _InfoLine(
                      label: 'File size',
                      value: _formatBytes(review.fileSizeBytes),
                    ),
                    const SizedBox(height: 12),
                    if (review.nativeCaptureSummary != null) ...[
                      Text(
                        review.nativeCaptureSummary!,
                        style: const TextStyle(
                          color: Color(0xFF8FD3FF),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (review.captureDebugInfo != null) ...[
                      _InfoLine(
                        label: 'Rotation source',
                        value: '${review.captureDebugInfo!['rotationSource']}',
                      ),
                      _InfoLine(
                        label: 'Base rotation',
                        value:
                            '${review.captureDebugInfo!['baseRotationLabel']} (${review.captureDebugInfo!['baseRotation']})',
                      ),
                      _InfoLine(
                        label: 'Display rotation',
                        value:
                            '${review.captureDebugInfo!['displayRotationLabel']} (${review.captureDebugInfo!['displayRotation']})',
                      ),
                      _InfoLine(
                        label: 'Target rotation',
                        value:
                            '${review.captureDebugInfo!['targetRotationLabel']} (${review.captureDebugInfo!['targetRotation']})',
                      ),
                      _InfoLine(
                        label: 'Written EXIF',
                        value:
                            '${review.captureDebugInfo!['outputExifOrientationLabel']} (${review.captureDebugInfo!['outputExifOrientation']})',
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      'The preview below is rendered from the captured bytes after applying EXIF orientation in Dart, so it does not depend on the platform image decoder handling EXIF for you.',
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Path',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      review.filePath,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _PreviewCard(
                title: 'EXIF Applied Preview',
                subtitle: review.appliedPreviewSubtitle,
                bytes: review.bakedPreviewBytes,
              ),
              const SizedBox(height: 16),
              _PreviewCard(
                title: 'Raw Pixel Matrix',
                subtitle:
                    'Decoded JPEG before applying EXIF orientation. Use this to compare with the EXIF-applied preview.',
                bytes: review.rawPreviewBytes,
              ),
            ],
          );
        },
      ),
    );
  }

  String _orientationLabel(int orientation) {
    switch (orientation) {
      case 1:
        return 'Normal';
      case 2:
        return 'Mirror horizontal';
      case 3:
        return 'Rotate 180';
      case 4:
        return 'Mirror vertical';
      case 5:
        return 'Mirror horizontal + rotate 90 CW';
      case 6:
        return 'Rotate 90 CW';
      case 7:
        return 'Mirror horizontal + rotate 90 CCW';
      case 8:
        return 'Rotate 90 CCW';
      default:
        return 'Unknown';
    }
  }

  String _formatBytes(int bytes) {
    const int kib = 1024;
    const int mib = kib * 1024;

    if (bytes >= mib) {
      return '${(bytes / mib).toStringAsFixed(2)} MiB';
    }
    if (bytes >= kib) {
      return '${(bytes / kib).toStringAsFixed(1)} KiB';
    }
    return '$bytes B';
  }
}

class _ReviewData {
  const _ReviewData({
    required this.filePath,
    required this.fileSizeBytes,
    required this.rawWidth,
    required this.rawHeight,
    required this.bakedWidth,
    required this.bakedHeight,
    required this.hasExifOrientation,
    required this.exifOrientation,
    required this.rawPreviewBytes,
    required this.bakedPreviewBytes,
    required this.captureDebugInfo,
  });

  final String filePath;
  final int fileSizeBytes;
  final int rawWidth;
  final int rawHeight;
  final int bakedWidth;
  final int bakedHeight;
  final bool hasExifOrientation;
  final int exifOrientation;
  final Uint8List rawPreviewBytes;
  final Uint8List bakedPreviewBytes;
  final Map<String, dynamic>? captureDebugInfo;

  bool get shouldApplyExif => hasExifOrientation && exifOrientation != 1;

  bool get normalizedToPortraitUp =>
      captureDebugInfo?['normalizedToPortraitUp'] == true;

  bool get nativeLayerUsesExifOrientation =>
      captureDebugInfo?['usesExifOrientation'] == true;

  String get previewTransformLabel {
    if (shouldApplyExif) {
      return 'Applied with img.bakeOrientation()';
    }
    if (normalizedToPortraitUp) {
      return 'No EXIF transform. The native capture already stored portraitUp pixels.';
    }
    return 'No EXIF rotation to apply';
  }

  String? get nativeCaptureSummary {
    if (!nativeLayerUsesExifOrientation) {
      return null;
    }
    final Object? baseRotationLabel = captureDebugInfo?['baseRotationLabel'];
    final Object? targetRotationLabel =
        captureDebugInfo?['targetRotationLabel'];
    final Object? outputExifOrientationLabel =
        captureDebugInfo?['outputExifOrientationLabel'];
    return 'Phone was captured in $baseRotationLabel. The Android layer stored portrait pixels as $targetRotationLabel, then wrote EXIF $outputExifOrientationLabel so image viewers can rotate it back for display.';
  }

  String get appliedPreviewSubtitle {
    if (shouldApplyExif) {
      return 'This preview uses the EXIF orientation tag written by the native camera layer.';
    }
    if (normalizedToPortraitUp) {
      return 'This file already stores portraitUp pixels, so no EXIF transform was needed.';
    }
    return 'No EXIF transform was needed for this file.';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111926),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.title,
    required this.subtitle,
    required this.bytes,
  });

  final String title;
  final String subtitle;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: Colors.black,
              constraints: const BoxConstraints(minHeight: 220),
              width: double.infinity,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.white54)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
