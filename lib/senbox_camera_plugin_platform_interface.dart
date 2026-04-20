import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/enums/camera_lens.dart';
import 'senbox_camera_plugin_method_channel.dart';

abstract class SenboxCameraPluginPlatform extends PlatformInterface {
  SenboxCameraPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static SenboxCameraPluginPlatform _instance =
      MethodChannelSenboxCameraPlugin();

  static SenboxCameraPluginPlatform get instance => _instance;

  static set instance(SenboxCameraPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<String?> takePicture() {
    throw UnimplementedError('takePicture() has not been implemented.');
  }

  Future<Map<String, dynamic>?> getLastCaptureDebugInfo() {
    throw UnimplementedError(
      'getLastCaptureDebugInfo() has not been implemented.',
    );
  }

  Future<void> switchCameraLens({
    required SenboxCameraLensDirection lensDirection,
  }) {
    throw UnimplementedError('switchCameraLens() has not been implemented.');
  }

  Future<void> startVideoRecording() {
    throw UnimplementedError('startVideoRecording() has not been implemented.');
  }

  Future<void> pauseVideoRecording() {
    throw UnimplementedError('pauseVideoRecording() has not been implemented.');
  }

  Future<void> resumeVideoRecording() {
    throw UnimplementedError(
      'resumeVideoRecording() has not been implemented.',
    );
  }

  Future<double> setZoomLevel({required double zoomLevel}) {
    throw UnimplementedError('setZoomLevel() has not been implemented.');
  }

  Future<String?> stopVideoRecording() {
    throw UnimplementedError('stopVideoRecording() has not been implemented.');
  }
}
