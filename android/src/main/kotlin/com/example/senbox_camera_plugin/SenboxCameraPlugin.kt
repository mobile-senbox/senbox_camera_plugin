package com.example.senbox_camera_plugin

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

class SenboxCameraPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    companion object {
        private const val CHANNEL_NAME = "senbox_camera_plugin"
        private const val VIEW_TYPE = "senbox_camera_plugin/native_camera_preview"
        private const val MEDIA_PERMISSION_REQUEST_CODE = 46031
    }

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var lifecycleOwner: LifecycleOwner? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val permissionCallbacks = mutableListOf<(Boolean) -> Unit>()
    private var activeCameraView: NativeCameraPlatformView? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE,
            NativeCameraViewFactory(this)
        )
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "takePicture" -> withActiveCameraView(result) { cameraView ->
                cameraView.takePicture(result)
            }
            "getLastCaptureDebugInfo" -> withActiveCameraView(result) { cameraView ->
                result.success(cameraView.getLastCaptureDebugInfo())
            }
            "switchCameraLens" -> withActiveCameraView(result) { cameraView ->
                val lensDirection = call.argument<String>("lensDirection") ?: "back"
                cameraView.switchCameraLens(lensDirection, result)
            }
            "startVideoRecording" -> withActiveCameraView(result) { cameraView ->
                cameraView.startVideoRecording(result)
            }
            "pauseVideoRecording" -> withActiveCameraView(result) { cameraView ->
                cameraView.pauseVideoRecording(result)
            }
            "resumeVideoRecording" -> withActiveCameraView(result) { cameraView ->
                cameraView.resumeVideoRecording(result)
            }
            "setZoomLevel" -> withActiveCameraView(result) { cameraView ->
                val zoomLevel = call.argument<Double>("zoomLevel")
                if (zoomLevel == null) {
                    result.error("INVALID_ZOOM", "zoomLevel is required.", null)
                    return@withActiveCameraView
                }
                cameraView.setZoomLevel(zoomLevel, result)
            }
            "stopVideoRecording" -> withActiveCameraView(result) { cameraView ->
                cameraView.stopVideoRecording(result)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        activeCameraView = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        lifecycleOwner = binding.activity as? LifecycleOwner
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        clearActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        clearActivity()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != MEDIA_PERMISSION_REQUEST_CODE) {
            return false
        }

        val isGranted =
            grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        val callbacks = permissionCallbacks.toList()
        permissionCallbacks.clear()
        callbacks.forEach { it(isGranted) }
        return callbacks.isNotEmpty()
    }

    fun getActivity(): Activity? = activity

    fun getLifecycleOwner(): LifecycleOwner? = lifecycleOwner

    fun hasCameraPermission(): Boolean {
        val currentActivity = activity ?: return false
        return ContextCompat.checkSelfPermission(
            currentActivity,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun hasAudioPermission(): Boolean {
        val currentActivity = activity ?: return false
        return ContextCompat.checkSelfPermission(
            currentActivity,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun requestCameraPermission(onResult: (Boolean) -> Unit) {
        requestPermissions(arrayOf(Manifest.permission.CAMERA), onResult)
    }

    fun requestAudioPermission(onResult: (Boolean) -> Unit) {
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), onResult)
    }

    fun requestPermissions(
        permissions: Array<String>,
        onResult: (Boolean) -> Unit
    ) {
        val currentActivity = activity
        if (currentActivity == null) {
            onResult(false)
            return
        }

        val allGranted = permissions.all { permission ->
            ContextCompat.checkSelfPermission(
                currentActivity,
                permission
            ) == PackageManager.PERMISSION_GRANTED
        }
        if (allGranted) {
            onResult(true)
            return
        }

        permissionCallbacks.add(onResult)
        if (permissionCallbacks.size == 1) {
            ActivityCompat.requestPermissions(
                currentActivity,
                permissions,
                MEDIA_PERMISSION_REQUEST_CODE
            )
        }
    }

    fun setActiveCameraView(view: NativeCameraPlatformView) {
        activeCameraView = view
    }

    fun clearActiveCameraView(view: NativeCameraPlatformView) {
        if (activeCameraView === view) {
            activeCameraView = null
        }
    }

    private fun withActiveCameraView(
        result: Result,
        action: (NativeCameraPlatformView) -> Unit
    ) {
        val cameraView = activeCameraView
        if (cameraView == null) {
            result.error(
                "NO_ACTIVE_CAMERA_VIEW",
                "Native camera view is not ready. Render SenboxNativeCameraView first.",
                null
            )
            return
        }
        action(cameraView)
    }

    private fun clearActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
        lifecycleOwner = null

        val callbacks = permissionCallbacks.toList()
        permissionCallbacks.clear()
        callbacks.forEach { it(false) }
    }
}
