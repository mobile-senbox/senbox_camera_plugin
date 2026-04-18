import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../enums/camera_lens.dart';


class SenboxNativeCameraView extends StatelessWidget {
  const SenboxNativeCameraView({
    super.key,
    this.lensDirection = SenboxCameraLensDirection.back,
  });

  static const String viewType = 'senbox_camera_plugin/native_camera_preview';

  final SenboxCameraLensDirection lensDirection;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Native CameraX preview is only supported on Android.',
            style: TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return AndroidView(
      viewType: viewType,
      layoutDirection: Directionality.maybeOf(context),
      creationParams: <String, dynamic>{'lensDirection': lensDirection.name},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
