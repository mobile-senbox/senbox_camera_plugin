import 'package:cross_file/cross_file.dart';

import 'src/enums/camera_lens.dart';
import 'senbox_camera_plugin_platform_interface.dart';
export 'src/presentation/camera_view/senbox_native_camera_view.dart';
export 'src/enums/camera_lens.dart';

class SenboxCameraPlugin {
  Future<String?> getPlatformVersion() {
    return SenboxCameraPluginPlatform.instance.getPlatformVersion();
  }

  Future<XFile?> takePicture() async {
    final String? imagePath = await SenboxCameraPluginPlatform.instance
        .takePicture();
    if (imagePath == null || imagePath.isEmpty) {
      return null;
    }
    return XFile(imagePath);
  }

  Future<Map<String, dynamic>?> getLastCaptureDebugInfo() {
    return SenboxCameraPluginPlatform.instance.getLastCaptureDebugInfo();
  }

  Future<void> switchCameraLens({
    required SenboxCameraLensDirection lensDirection,
  }) {
    return SenboxCameraPluginPlatform.instance.switchCameraLens(
      lensDirection: lensDirection,
    );
  }

  Future<bool> checkAudioPermission() {
    return SenboxCameraPluginPlatform.instance.checkAudioPermission();
  }

  Future<bool> requestAudioPermission() {
    return SenboxCameraPluginPlatform.instance.requestAudioPermission();
  }

  Future<void> startVideoRecording() {
    return SenboxCameraPluginPlatform.instance.startVideoRecording();
  }

  Future<void> pauseVideoRecording() {
    return SenboxCameraPluginPlatform.instance.pauseVideoRecording();
  }

  Future<void> resumeVideoRecording() {
    return SenboxCameraPluginPlatform.instance.resumeVideoRecording();
  }

  Future<double> setZoomLevel({required double zoomLevel}) {
    return SenboxCameraPluginPlatform.instance.setZoomLevel(
      zoomLevel: zoomLevel,
    );
  }

  Future<XFile?> stopVideoRecording() async {
    final String? videoPath = await SenboxCameraPluginPlatform.instance
        .stopVideoRecording();
    if (videoPath == null || videoPath.isEmpty) {
      return null;
    }
    return XFile(videoPath);
  }

  Future<void> clearCache() {
    return SenboxCameraPluginPlatform.instance.clearCache();
  }

  Future<bool> openAppSettings() {
    return SenboxCameraPluginPlatform.instance.openAppSettings();
  }
}
