import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:senbox_camera_plugin/senbox_camera_plugin.dart';

import 'review.dart';
import 'review_video.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Example(),
    );
  }
}

class Example extends StatefulWidget {
  const Example({super.key});
  @override
  State<Example> createState() => _ExampleState();
}

class _ExampleState extends State<Example> {
  final SenboxCameraPlugin _senboxCameraPlugin = SenboxCameraPlugin();

  SenboxCameraLensDirection _lensDirection = SenboxCameraLensDirection.back;
  double _zoomLevel = 1.0;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _showAudioPermissionSettingsButton = false;
  String _status = 'Ready';
  XFile? _capturedImage;
  XFile? _capturedVideo;

  Future<void> _takePicture() async {
    try {
      final XFile? file = await _senboxCameraPlugin.takePicture();
      final Map<String, dynamic>? captureDebugInfo = await _senboxCameraPlugin
          .getLastCaptureDebugInfo();
      if (!mounted) {
        return;
      }
      setState(() {
        _capturedImage = file;
        _status = file == null
            ? 'Capture failed.'
            : 'Captured image: ${file.path}';
      });
      if (file == null) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ReviewPage(imageFile: file, captureDebugInfo: captureDebugInfo),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Take picture error: $e';
      });
    }
  }

  Future<void> _switchCameraLens() async {
    final SenboxCameraLensDirection nextLensDirection =
        _lensDirection == SenboxCameraLensDirection.back
        ? SenboxCameraLensDirection.front
        : SenboxCameraLensDirection.back;

    try {
      await _senboxCameraPlugin.switchCameraLens(
        lensDirection: nextLensDirection,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _lensDirection = nextLensDirection;
        _zoomLevel = 1.0;
        _status =
            'Switched lens to: ${nextLensDirection.name} (${_zoomLevel.toStringAsFixed(1)}x)';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Switch lens error: $e';
      });
    }
  }

  Future<void> _startVideoRecording() async {
    try {
      final bool hasAudioPermission = await _senboxCameraPlugin
          .checkAudioPermission();
      if (!hasAudioPermission) {
        final bool isAudioPermissionGranted = await _senboxCameraPlugin
            .requestAudioPermission();
        if (!mounted) {
          return;
        }
        if (!isAudioPermissionGranted) {
          setState(() {
            _showAudioPermissionSettingsButton = true;
            _status =
                'Bạn chưa cấp quyền audio. Hãy cấp quyền Microphone cho app.';
          });
          _showAudioPermissionDeniedMessage();
          return;
        }
      }

      await _senboxCameraPlugin.startVideoRecording();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _showAudioPermissionSettingsButton = false;
        _status = 'Video recording started.';
      });
    } on PlatformException catch (e) {
      if (!mounted) {
        return;
      }
      if (e.code == 'AUDIO_PERMISSION_DENIED' ||
          e.code == 'AUDIO_PERMISSION_REQUIRED') {
        setState(() {
          _showAudioPermissionSettingsButton = true;
          _status =
              'Bạn chưa cấp quyền audio. Hãy cấp quyền Microphone cho app.';
        });
        _showAudioPermissionDeniedMessage();
        return;
      }
      setState(() {
        _showAudioPermissionSettingsButton = false;
        _status = 'Start video error: $e';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _showAudioPermissionSettingsButton = false;
        _status = 'Start video error: $e';
      });
    }
  }

  Future<void> _openAppPermissionSettings() async {
    final bool didOpenSettings = await _senboxCameraPlugin.openAppSettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _status = didOpenSettings
          ? 'Đã mở cài đặt app. Hãy cấp quyền Microphone rồi quay lại Start Video.'
          : 'Không thể mở cài đặt app. Hãy mở Settings và cấp quyền Microphone cho app.';
    });
  }

  void _showAudioPermissionDeniedMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            'Bạn chưa cấp quyền audio. Hãy cấp quyền Microphone cho app.',
          ),
          action: SnackBarAction(
            label: 'Mở quyền',
            onPressed: _openAppPermissionSettings,
          ),
        ),
      );
  }

  Future<void> _pauseVideoRecording() async {
    try {
      await _senboxCameraPlugin.pauseVideoRecording();
      if (!mounted) {
        return;
      }
      setState(() {
        _isPaused = true;
        _status = 'Video recording paused.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Pause video error: $e';
      });
    }
  }

  Future<void> _resumeVideoRecording() async {
    try {
      await _senboxCameraPlugin.resumeVideoRecording();
      if (!mounted) {
        return;
      }
      setState(() {
        _isPaused = false;
        _status = 'Video recording resumed.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Resume video error: $e';
      });
    }
  }

  Future<void> _stopVideoRecording() async {
    try {
      final XFile? file = await _senboxCameraPlugin.stopVideoRecording();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecording = false;
        _isPaused = false;
        _capturedVideo = file;
        _status = file == null
            ? 'Stop video failed.'
            : 'Recorded video: ${file.path}';
      });
      if (file == null) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReviewVideoPage(videoFile: file)),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Stop video error: $e';
      });
    }
  }

  Future<void> _zoomCamera(double zoomLevel) async {
    try {
      final double appliedZoom = await _senboxCameraPlugin.setZoomLevel(
        zoomLevel: zoomLevel,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _zoomLevel = appliedZoom;
        _status = 'Zoom set to ${appliedZoom.toStringAsFixed(1)}x';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Set zoom error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('CameraX PlatformView Example')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SenboxNativeCameraView(lensDirection: _lensDirection),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _status,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Image: ${_capturedImage?.path ?? '-'}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Zoom: ${_zoomLevel.toStringAsFixed(1)}x',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Video: ${_capturedVideo?.path ?? '-'}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _ActionButton(label: 'Take Picture', onTap: _takePicture),
                  _ActionButton(
                    label: 'Switch Lens',
                    onTap: _isRecording ? null : _switchCameraLens,
                  ),
                  _ActionButton(
                    label: 'Start Video',
                    onTap: _isRecording ? null : _startVideoRecording,
                  ),
                  if (_showAudioPermissionSettingsButton)
                    _ActionButton(
                      label: 'Mở quyền audio',
                      onTap: _openAppPermissionSettings,
                    ),
                  _ActionButton(
                    label: 'Pause Video',
                    onTap: _isRecording && !_isPaused
                        ? _pauseVideoRecording
                        : null,
                  ),
                  _ActionButton(
                    label: 'Resume Video',
                    onTap: _isRecording && _isPaused
                        ? _resumeVideoRecording
                        : null,
                  ),
                  _ActionButton(
                    label: 'Stop Video',
                    onTap: _isRecording ? _stopVideoRecording : null,
                  ),
                  _ActionButton(
                    label: 'Zoom 1x',
                    onTap: () => _zoomCamera(1.0),
                  ),
                  _ActionButton(
                    label: 'Zoom 1.5x',
                    onTap: () => _zoomCamera(1.5),
                  ),
                  _ActionButton(
                    label: 'Zoom 2.0x',
                    onTap: () => _zoomCamera(2.0),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: onTap == null ? Colors.grey : Colors.blue,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}
