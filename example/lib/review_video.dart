import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ReviewVideoPage extends StatefulWidget {
  const ReviewVideoPage({super.key, required this.videoFile});

  final XFile videoFile;

  @override
  State<ReviewVideoPage> createState() => _ReviewVideoPageState();
}

class _ReviewVideoPageState extends State<ReviewVideoPage> {
  late final VideoPlayerController _controller;
  late final Future<_VideoReviewData> _reviewFuture = _loadReviewData();

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoFile.path));
  }

  Future<_VideoReviewData> _loadReviewData() async {
    final File file = File(widget.videoFile.path);
    final FileStat stat = await file.stat();
    if (stat.type == FileSystemEntityType.notFound) {
      throw StateError('Recorded video file was not found.');
    }

    await _controller.initialize();
    await _controller.setLooping(true);
    await _controller.play();

    final Size dimensions = _controller.value.size;
    return _VideoReviewData(
      filePath: widget.videoFile.path,
      fileSizeBytes: stat.size,
      duration: _controller.value.duration,
      width: dimensions.width,
      height: dimensions.height,
    );
  }

  Future<void> _togglePlayback() async {
    if (!_controller.value.isInitialized) {
      return;
    }
    if (_controller.value.isPlaying) {
      await _controller.pause();
      return;
    }
    await _controller.play();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1016),
      appBar: AppBar(
        title: const Text('Recorded Video Review'),
        backgroundColor: const Color(0xFF111926),
      ),
      body: FutureBuilder<_VideoReviewData>(
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
                  'Unable to load video review.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            );
          }

          final _VideoReviewData review = snapshot.requireData;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionCard(
                title: 'Video Summary',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoLine(
                      label: 'Duration',
                      value: _formatDuration(review.duration),
                    ),
                    _InfoLine(
                      label: 'Resolution',
                      value:
                          '${review.width.toStringAsFixed(0)} x ${review.height.toStringAsFixed(0)}',
                    ),
                    _InfoLine(
                      label: 'File size',
                      value: _formatBytes(review.fileSizeBytes),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'The preview below plays the recorded MP4 directly from disk using the platform video decoder.',
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
              _SectionCard(
                title: 'Preview',
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) {
                    final bool isInitialized = value.isInitialized;
                    final double aspectRatio =
                        isInitialized && value.aspectRatio > 0
                        ? value.aspectRatio
                        : (review.width > 0 && review.height > 0
                              ? review.width / review.height
                              : 9 / 16);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: isInitialized ? _togglePlayback : null,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              color: Colors.black,
                              child: AspectRatio(
                                aspectRatio: aspectRatio,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (isInitialized) VideoPlayer(_controller),
                                    Container(color: Colors.black26),
                                    Center(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Icon(
                                            value.isPlaying
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            color: Colors.white,
                                            size: 32,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            padding: EdgeInsets.zero,
                            colors: const VideoProgressColors(
                              playedColor: Color(0xFF8FD3FF),
                              bufferedColor: Colors.white24,
                              backgroundColor: Colors.white10,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: isInitialized ? _togglePlayback : null,
                              icon: Icon(
                                value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              label: Text(value.isPlaying ? 'Pause' : 'Play'),
                            ),
                            const Spacer(),
                            Text(
                              '${_formatDuration(value.position)} / ${_formatDuration(review.duration)}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
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

  String _formatDuration(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _VideoReviewData {
  const _VideoReviewData({
    required this.filePath,
    required this.fileSizeBytes,
    required this.duration,
    required this.width,
    required this.height,
  });

  final String filePath;
  final int fileSizeBytes;
  final Duration duration;
  final double width;
  final double height;
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
          const SizedBox(width: 12),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
