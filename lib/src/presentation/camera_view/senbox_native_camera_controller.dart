import 'dart:developer';

import 'package:cross_file/cross_file.dart';
import '../../enums/camera_lens.dart';
import '../../../senbox_camera_plugin_platform_interface.dart';

abstract class SenboxCameraNativeController {
  Future<XFile?> takePicture();
  Future<void> switchCameraLens({
    required SenboxCameraLensDirection lensDirection,
  });
  Future<void> startVideoRecording();
  Future<void> pauseVideoRecording();
  Future<void> resumeVideoRecording();
  Future<double> setZoomLevel({required double zoomLevel});
  Future<XFile?> stopVideoRecording();
  Future<void> clearCache();
}

class SenboxNativeCameraControllerImp implements SenboxCameraNativeController {
  final SenboxCameraPluginPlatform _platform;

  SenboxNativeCameraControllerImp({SenboxCameraPluginPlatform? platform})
    : _platform = platform ?? SenboxCameraPluginPlatform.instance;

  @override
  Future<XFile?> takePicture() async {
    try {
      final String? imagePath = await _platform.takePicture();
      if (imagePath != null && imagePath.isNotEmpty) {
        return XFile(imagePath);
      }
      return null;
    } catch (e) {
      log('error for capture camera: $e');
      return null;
    }
  }

  @override
  Future<void> switchCameraLens({
    required SenboxCameraLensDirection lensDirection,
  }) async {
    try {
      await _platform.switchCameraLens(lensDirection: lensDirection);
    } catch (e) {
      log('error for switch camera lens: $e');
    }
  }

  @override
  Future<void> startVideoRecording() async {
    try {
      await _platform.startVideoRecording();
    } catch (e) {
      log('error for start video recording: $e');
    }
  }

  @override
  Future<void> pauseVideoRecording() async {
    try {
      await _platform.pauseVideoRecording();
    } catch (e) {
      log('error for pause video recording: $e');
    }
  }

  @override
  Future<void> resumeVideoRecording() async {
    try {
      await _platform.resumeVideoRecording();
    } catch (e) {
      log('error for resume video recording: $e');
    }
  }

  @override
  Future<double> setZoomLevel({required double zoomLevel}) async {
    try {
      return await _platform.setZoomLevel(zoomLevel: zoomLevel);
    } catch (e) {
      log('error for set zoom level: $e');
      return zoomLevel;
    }
  }

  @override
  Future<XFile?> stopVideoRecording() async {
    try {
      final String? videoPath = await _platform.stopVideoRecording();
      if (videoPath != null && videoPath.isNotEmpty) {
        return XFile(videoPath);
      }
      return null;
    } catch (e) {
      log('error for stop video recording: $e');
      return null;
    }
  }

  @override
  Future<void> clearCache() async {
    try {
      await _platform.clearCache();
    } catch (e) {
      log('error for clear cache: $e');
    }
  }
}
