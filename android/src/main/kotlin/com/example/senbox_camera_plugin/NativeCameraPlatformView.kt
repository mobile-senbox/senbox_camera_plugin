package com.example.senbox_camera_plugin

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.graphics.Color
import android.util.Log
import android.view.Gravity
import android.view.Surface
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.File
import java.util.Locale

class NativeCameraPlatformView(
    context: Context,
    private val plugin: SenboxCameraPlugin,
    creationParams: Map<String, Any?>?
) : PlatformView {
    companion object {
        private const val DIRECT_CAMERA_PERMISSION_REQUEST_CODE = 46032
        private const val TAG = "SenboxNativeCameraView"
    }

    private val rootContext = context
    private val container = FrameLayout(context)
    private val previewView = PreviewView(context)
    private val statusView = TextView(context)
    private val requestedLensFacing = parseLensFacing(creationParams?.get("lensDirection") as? String)

    private var currentLensFacing = requestedLensFacing
    private var cameraProvider: ProcessCameraProvider? = null
    private var boundCamera: Camera? = null
    private var previewUseCase: Preview? = null
    private var imageCaptureUseCase: ImageCapture? = null
    private var videoCaptureUseCase: VideoCapture<Recorder>? = null
    private var activeRecording: Recording? = null
    private var currentVideoPath: String? = null
    private var requestedZoomRatio = 1f
    private var pendingStopResult: MethodChannel.Result? = null
    private var isDisposed = false
    private var attachRetryCount = 0
    private var hasRequestedDirectPermission = false

    init {
        previewView.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        previewView.scaleType = PreviewView.ScaleType.FILL_CENTER

        statusView.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ).apply {
            gravity = Gravity.CENTER
        }
        statusView.gravity = Gravity.CENTER
        statusView.setTextColor(Color.WHITE)
        statusView.textSize = 16f
        statusView.setPadding(48, 48, 48, 48)

        container.setBackgroundColor(Color.BLACK)
        container.addView(previewView)
        container.addView(statusView)

        plugin.setActiveCameraView(this)
        startWhenReady()
    }

    override fun getView(): View = container

    override fun dispose() {
        isDisposed = true
        stopRecordingIfNeeded()
        pendingStopResult?.error(
            "VIEW_DISPOSED",
            "Camera view was disposed before stop finished.",
            null
        )
        pendingStopResult = null
        cameraProvider?.unbindAll()
        boundCamera = null
        previewUseCase = null
        imageCaptureUseCase = null
        videoCaptureUseCase = null
        cameraProvider = null
        plugin.clearActiveCameraView(this)
    }

    fun takePicture(result: MethodChannel.Result) {
        if (isDisposed) {
            result.error("VIEW_DISPOSED", "Camera view is already disposed.", null)
            return
        }

        val imageCapture = imageCaptureUseCase
        if (imageCapture == null) {
            result.error("CAMERA_NOT_READY", "ImageCapture use case is not ready.", null)
            return
        }

        val host = resolveHost()
        if (host == null) {
            result.error("NO_HOST", "No host activity is available.", null)
            return
        }

        val outputFile = createMediaFile("jpg")
        val outputOptions = ImageCapture.OutputFileOptions.Builder(outputFile).build()
        imageCapture.targetRotation = currentDisplayRotation()

        imageCapture.takePicture(
            outputOptions,
            ContextCompat.getMainExecutor(host.first),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                    result.success(outputFile.absolutePath)
                }

                override fun onError(exception: ImageCaptureException) {
                    result.error(
                        "TAKE_PICTURE_FAILED",
                        "Failed to capture image: ${exception.message}",
                        null
                    )
                }
            }
        )
    }

    fun switchCameraLens(
        lensDirection: String,
        result: MethodChannel.Result
    ) {
        if (activeRecording != null) {
            result.error("VIDEO_RECORDING_ACTIVE", "Stop video recording before switching lens.", null)
            return
        }

        currentLensFacing = parseLensFacing(lensDirection)
        requestedZoomRatio = 1f
        boundCamera = null
        startWhenReady()
        result.success(null)
    }

    fun startVideoRecording(result: MethodChannel.Result) {
        if (isDisposed) {
            result.error("VIEW_DISPOSED", "Camera view is already disposed.", null)
            return
        }

        if (activeRecording != null) {
            result.error("VIDEO_RECORDING_ACTIVE", "Video recording is already running.", null)
            return
        }

        val videoCapture = videoCaptureUseCase
        if (videoCapture == null) {
            result.error("CAMERA_NOT_READY", "VideoCapture use case is not ready.", null)
            return
        }

        val host = resolveHost()
        if (host == null) {
            result.error("NO_HOST", "No host activity is available.", null)
            return
        }

        val outputFile = createMediaFile("mp4")
        currentVideoPath = outputFile.absolutePath
        val outputOptions = FileOutputOptions.Builder(outputFile).build()

        try {
            val pendingRecording = videoCapture.output.prepareRecording(host.first, outputOptions)
            activeRecording = pendingRecording.start(ContextCompat.getMainExecutor(host.first)) { event ->
                if (event is VideoRecordEvent.Finalize) {
                    onVideoRecordFinalize(event)
                }
            }
            result.success(null)
        } catch (e: Exception) {
            activeRecording = null
            currentVideoPath = null
            result.error(
                "START_VIDEO_FAILED",
                "Unable to start video recording: ${e.message}",
                null
            )
        }
    }

    fun pauseVideoRecording(result: MethodChannel.Result) {
        val recording = activeRecording
        if (recording == null) {
            result.error("VIDEO_NOT_RECORDING", "No active video recording to pause.", null)
            return
        }

        try {
            recording.pause()
            result.success(null)
        } catch (e: Exception) {
            result.error(
                "PAUSE_VIDEO_FAILED",
                "Unable to pause video recording: ${e.message}",
                null
            )
        }
    }

    fun resumeVideoRecording(result: MethodChannel.Result) {
        val recording = activeRecording
        if (recording == null) {
            result.error("VIDEO_NOT_RECORDING", "No active video recording to resume.", null)
            return
        }

        try {
            recording.resume()
            result.success(null)
        } catch (e: Exception) {
            result.error(
                "RESUME_VIDEO_FAILED",
                "Unable to resume video recording: ${e.message}",
                null
            )
        }
    }

    fun setZoomLevel(
        zoomLevel: Double,
        result: MethodChannel.Result
    ) {
        if (zoomLevel <= 0.0) {
            result.error("INVALID_ZOOM", "zoomLevel must be greater than 0.", null)
            return
        }

        val camera = boundCamera
        if (camera == null) {
            result.error("CAMERA_NOT_READY", "Camera is not ready for zoom.", null)
            return
        }

        val zoomState = camera.cameraInfo.zoomState.value
        if (zoomState == null) {
            result.error("ZOOM_UNAVAILABLE", "Zoom state is unavailable.", null)
            return
        }

        val clampedZoom = zoomLevel.toFloat().coerceIn(
            zoomState.minZoomRatio,
            zoomState.maxZoomRatio
        )
        requestedZoomRatio = clampedZoom

        try {
            val zoomFuture = camera.cameraControl.setZoomRatio(clampedZoom)
            zoomFuture.addListener(
                {
                    try {
                        zoomFuture.get()
                        result.success(clampedZoom.toDouble())
                    } catch (e: Exception) {
                        result.error(
                            "SET_ZOOM_FAILED",
                            "Unable to set zoom level: ${e.message}",
                            null
                        )
                    }
                },
                ContextCompat.getMainExecutor(rootContext)
            )
        } catch (e: Exception) {
            result.error(
                "SET_ZOOM_FAILED",
                "Unable to set zoom level: ${e.message}",
                null
            )
        }
    }

    fun stopVideoRecording(result: MethodChannel.Result) {
        val recording = activeRecording
        if (recording == null) {
            result.error("VIDEO_NOT_RECORDING", "No active video recording to stop.", null)
            return
        }

        if (pendingStopResult != null) {
            result.error("STOP_IN_PROGRESS", "Stop video recording is already in progress.", null)
            return
        }

        pendingStopResult = result

        try {
            recording.stop()
        } catch (e: Exception) {
            pendingStopResult = null
            result.error(
                "STOP_VIDEO_FAILED",
                "Unable to stop video recording: ${e.message}",
                null
            )
        }
    }

    private fun onVideoRecordFinalize(event: VideoRecordEvent.Finalize) {
        val stopResult = pendingStopResult
        val outputPath = currentVideoPath

        pendingStopResult = null
        activeRecording = null
        currentVideoPath = null

        if (stopResult == null) {
            return
        }

        if (event.hasError()) {
            stopResult.error(
                "VIDEO_RECORDING_FAILED",
                "Video finalize failed with error code: ${event.error}",
                null
            )
            return
        }

        stopResult.success(outputPath)
    }

    private fun startWhenReady() {
        val host = resolveHost()
        if (host == null) {
            if (attachRetryCount < 20) {
                attachRetryCount += 1
                showStatus("Waiting for Flutter activity...")
                container.postDelayed({ startWhenReady() }, 150L)
                return
            }
            showStatus(buildHostMissingMessage())
            return
        }
        attachRetryCount = 0
        val (activity, lifecycleOwner) = host

        if (hasCameraPermission(activity)) {
            startCamera(activity, lifecycleOwner)
            return
        }

        if (plugin.getActivity() != null) {
            showStatus("Requesting camera permission...")
            plugin.requestCameraPermission { isGranted ->
                container.post {
                    if (isDisposed) {
                        return@post
                    }
                    if (!isGranted) {
                        showStatus("Camera permission denied.")
                        return@post
                    }
                    val currentHost = resolveHost()
                    if (currentHost == null) {
                        container.postDelayed({ startWhenReady() }, 150L)
                        return@post
                    }
                    startCamera(currentHost.first, currentHost.second)
                }
            }
            return
        }

        if (!hasRequestedDirectPermission) {
            hasRequestedDirectPermission = true
            showStatus("Requesting camera permission...")
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.CAMERA),
                DIRECT_CAMERA_PERMISSION_REQUEST_CODE
            )
        } else {
            showStatus("Waiting for camera permission...")
        }
        container.postDelayed({ startWhenReady() }, 300L)
    }

    private fun startCamera(
        activity: Activity,
        lifecycleOwner: LifecycleOwner
    ) {
        showStatus("Opening camera...")
        val providerFuture = ProcessCameraProvider.getInstance(activity)
        providerFuture.addListener(
            {
                if (isDisposed) {
                    return@addListener
                }

                try {
                    val provider = providerFuture.get()
                    cameraProvider = provider
                    val selector = resolveCameraSelector(provider)
                    if (selector == null) {
                        showStatus("No available camera.")
                        boundCamera = null
                        return@addListener
                    }

                    val preview = Preview.Builder().build().also { useCase ->
                        useCase.setSurfaceProvider(previewView.surfaceProvider)
                    }

                    val imageCapture = ImageCapture.Builder()
                        .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                        .setTargetRotation(currentDisplayRotation())
                        .build()

                    val recorder = Recorder.Builder()
                        .setQualitySelector(
                            QualitySelector.from(
                                Quality.HD,
                                FallbackStrategy.higherQualityOrLowerThan(Quality.SD)
                            )
                        )
                        .build()
                    val videoCapture = VideoCapture.withOutput(recorder)

                    provider.unbindAll()
                    boundCamera = null
                    previewUseCase = preview
                    imageCaptureUseCase = imageCapture
                    videoCaptureUseCase = videoCapture
                    val camera = provider.bindToLifecycle(
                        lifecycleOwner,
                        selector,
                        preview,
                        imageCapture,
                        videoCapture
                    )
                    boundCamera = camera
                    applyRequestedZoom(camera)
                    hideStatus()
                } catch (_: Exception) {
                    boundCamera = null
                    showStatus("Unable to start CameraX preview.")
                }
            },
            ContextCompat.getMainExecutor(activity)
        )
    }

    private fun resolveCameraSelector(provider: ProcessCameraProvider): CameraSelector? {
        val requestedSelector = CameraSelector.Builder()
            .requireLensFacing(currentLensFacing)
            .build()

        return try {
            when {
                provider.hasCamera(requestedSelector) -> requestedSelector
                provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA) ->
                    CameraSelector.DEFAULT_BACK_CAMERA
                provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) ->
                    CameraSelector.DEFAULT_FRONT_CAMERA
                else -> null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun stopRecordingIfNeeded() {
        try {
            activeRecording?.stop()
        } catch (_: Exception) {
        }
        activeRecording = null
        currentVideoPath = null
    }

    private fun showStatus(message: String) {
        Log.d(TAG, message)
        statusView.text = message
        statusView.visibility = View.VISIBLE
    }

    private fun hideStatus() {
        Log.d(TAG, "Camera preview started.")
        statusView.visibility = View.GONE
    }

    private fun applyRequestedZoom(camera: Camera) {
        val zoomState = camera.cameraInfo.zoomState.value ?: return
        val clampedZoom = requestedZoomRatio.coerceIn(
            zoomState.minZoomRatio,
            zoomState.maxZoomRatio
        )
        requestedZoomRatio = clampedZoom
        try {
            camera.cameraControl.setZoomRatio(clampedZoom)
        } catch (_: Exception) {
        }
    }

    private fun parseLensFacing(lensDirection: String?): Int {
        return when (lensDirection?.lowercase(Locale.US)) {
            "front" -> CameraSelector.LENS_FACING_FRONT
            else -> CameraSelector.LENS_FACING_BACK
        }
    }

    private fun resolveHost(): Pair<Activity, LifecycleOwner>? {
        val pluginActivity = plugin.getActivity()
        if (pluginActivity != null) {
            val pluginLifecycleOwner = plugin.getLifecycleOwner()
                ?: (pluginActivity as? LifecycleOwner)
                ?: ProcessLifecycleOwner.get()
            return pluginActivity to pluginLifecycleOwner
        }

        val contextActivity = findActivity(rootContext) ?: return null
        val contextLifecycleOwner = (contextActivity as? LifecycleOwner) ?: ProcessLifecycleOwner.get()
        return contextActivity to contextLifecycleOwner
    }

    private fun hasCameraPermission(activity: Activity): Boolean {
        return ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun findActivity(context: Context): Activity? {
        var currentContext: Context? = context
        while (currentContext is ContextWrapper) {
            if (currentContext is Activity) {
                return currentContext
            }
            currentContext = currentContext.baseContext
        }
        return null
    }

    private fun createMediaFile(extension: String): File {
        val outputDir = File(rootContext.cacheDir, "senbox_camera_plugin")
        if (!outputDir.exists()) {
            outputDir.mkdirs()
        }
        return File.createTempFile("sbx_${System.currentTimeMillis()}_", ".$extension", outputDir)
    }

    private fun currentDisplayRotation(): Int {
        return previewView.display?.rotation ?: Surface.ROTATION_0
    }

    private fun buildHostMissingMessage(): String {
        val pluginActivity = plugin.getActivity()?.javaClass?.simpleName ?: "null"
        val pluginLifecycle = plugin.getLifecycleOwner()?.javaClass?.simpleName ?: "null"
        val contextActivity = findActivity(rootContext)?.javaClass?.simpleName ?: "null"
        val contextClass = rootContext.javaClass.simpleName
        return "Host missing. pluginActivity=$pluginActivity, " +
            "pluginLifecycle=$pluginLifecycle, contextActivity=$contextActivity, " +
            "context=$contextClass"
    }
}
