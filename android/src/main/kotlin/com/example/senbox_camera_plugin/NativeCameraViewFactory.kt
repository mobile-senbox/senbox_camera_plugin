package com.example.senbox_camera_plugin

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class NativeCameraViewFactory(
    private val plugin: SenboxCameraPlugin
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(
        context: Context,
        viewId: Int,
        args: Any?
    ): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val creationParams = args as? Map<String, Any?>
        return NativeCameraPlatformView(
            context = context,
            plugin = plugin,
            creationParams = creationParams
        )
    }
}
