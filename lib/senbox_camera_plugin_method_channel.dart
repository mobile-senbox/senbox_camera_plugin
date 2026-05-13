import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/enums/camera_lens.dart';
import 'senbox_camera_plugin_platform_interface.dart';

class MethodChannelSenboxCameraPlugin extends SenboxCameraPluginPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('senbox_camera_plugin');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<String?> takePicture() async {
    final path = await methodChannel.invokeMethod<String>('takePicture');
    return path;
  }

  @override
  Future<Map<String, dynamic>?> getLastCaptureDebugInfo() async {
    try {
      final Map<dynamic, dynamic>? info = await methodChannel
          .invokeMethod<Map<dynamic, dynamic>>('getLastCaptureDebugInfo');
      if (info == null) {
        return null;
      }
      return Map<String, dynamic>.from(info);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> switchCameraLens({
    required SenboxCameraLensDirection lensDirection,
  }) async {
    await methodChannel.invokeMethod<void>(
      'switchCameraLens',
      <String, dynamic>{'lensDirection': lensDirection.name},
    );
  }

  @override
  Future<bool> checkAudioPermission() async {
    final bool? isGranted = await methodChannel.invokeMethod<bool>(
      'checkAudioPermission',
    );
    return isGranted ?? false;
  }

  @override
  Future<bool> requestAudioPermission() async {
    final bool? isGranted = await methodChannel.invokeMethod<bool>(
      'requestAudioPermission',
    );
    return isGranted ?? false;
  }

  @override
  Future<void> startVideoRecording() async {
    await methodChannel.invokeMethod<void>('startVideoRecording');
  }

  @override
  Future<void> pauseVideoRecording() async {
    await methodChannel.invokeMethod<void>('pauseVideoRecording');
  }

  @override
  Future<void> resumeVideoRecording() async {
    await methodChannel.invokeMethod<void>('resumeVideoRecording');
  }

  @override
  Future<double> setZoomLevel({required double zoomLevel}) async {
    final num? appliedZoom = await methodChannel.invokeMethod<num>(
      'setZoomLevel',
      <String, dynamic>{'zoomLevel': zoomLevel},
    );
    return (appliedZoom ?? zoomLevel).toDouble();
  }

  @override
  Future<String?> stopVideoRecording() async {
    final path = await methodChannel.invokeMethod<String>('stopVideoRecording');
    return path;
  }

  @override
  Future<void> clearCache() async {
    await methodChannel.invokeMethod<void>('clearCache');
  }

  @override
  Future<bool> openAppSettings() async {
    final bool? didOpenSettings = await methodChannel.invokeMethod<bool>(
      'openAppSettings',
    );
    return didOpenSettings ?? false;
  }
}
