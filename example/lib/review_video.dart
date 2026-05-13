import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class ReviewVideoPage extends StatefulWidget {
  const ReviewVideoPage({super.key, required this.videoFile});

  final XFile videoFile;

  @override
  State<ReviewVideoPage> createState() => _ReviewVideoPageState();
}

class _ReviewVideoPageState extends State<ReviewVideoPage> {
  late final Player _player;
  late final VideoController _controller;
  late final Future<_VideoReviewData> _reviewFuture = _loadReviewData();

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
  }

  Future<_VideoReviewData> _loadReviewData() async {
    final File file = File(widget.videoFile.path);
    final FileStat stat = await file.stat();
    if (stat.type == FileSystemEntityType.notFound) {
      throw StateError('Recorded video file was not found.');
    }

    await _player.open(Media(widget.videoFile.path));
    await _player.setPlaylistMode(PlaylistMode.loop);

    // Wait slightly for metadata to load
    for (int i = 0; i < 20; i++) {
      if (_player.state.duration != Duration.zero && (_player.state.width ?? 0) > 0) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final Duration duration = _player.state.duration;
    final double width = (_player.state.width ?? 0).toDouble();
    final double height = (_player.state.height ?? 0).toDouble();

    return _VideoReviewData(
      filePath: widget.videoFile.path,
      fileSizeBytes: stat.size,
      duration: duration,
      width: width,
      height: height,
    );
  }

  Future<void> _togglePlayback() async {
    if (_player.state.playing) {
      await _player.pause();
      return;
    }
    await _player.play();
  }

  @override
  void dispose() {
    _player.dispose();
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
                child: StreamBuilder<bool>(
                  stream: _player.stream.playing,
                  initialData: _player.state.playing,
                  builder: (context, playingSnapshot) {
                    final isPlaying = playingSnapshot.data ?? false;

                    return StreamBuilder<Duration>(
                      stream: _player.stream.position,
                      initialData: _player.state.position,
                      builder: (context, positionSnapshot) {
                        final position = positionSnapshot.data ?? Duration.zero;
                        final double aspectRatio = review.width > 0 && review.height > 0
                                ? review.width / review.height
                                : 9 / 16;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: _togglePlayback,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  color: Colors.black,
                                  child: AspectRatio(
                                    aspectRatio: aspectRatio,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Video(controller: _controller),
                                        if (!isPlaying) Container(color: Colors.black26),
                                        if (!isPlaying) Center(
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: const Padding(
                                              padding: EdgeInsets.all(14),
                                              child: Icon(
                                                Icons.play_arrow_rounded,
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
                            SliderTheme(
                              data: const SliderThemeData(
                                trackHeight: 4,
                                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
                                activeTrackColor: Color(0xFF8FD3FF),
                                inactiveTrackColor: Colors.white10,
                                thumbColor: Color(0xFF8FD3FF),
                              ),
                              child: Slider(
                                value: position.inMilliseconds.toDouble().clamp(0, review.duration.inMilliseconds.toDouble()),
                                max: review.duration.inMilliseconds.toDouble() > 0 ? review.duration.inMilliseconds.toDouble() : 1,
                                onChanged: (value) {
                                  _player.seek(Duration(milliseconds: value.toInt()));
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: _togglePlayback,
                                  icon: Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                  label: Text(isPlaying ? 'Pause' : 'Play'),
                                ),
                                const Spacer(),
                                Text(
                                  '${_formatDuration(position)} / ${_formatDuration(review.duration)}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
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
