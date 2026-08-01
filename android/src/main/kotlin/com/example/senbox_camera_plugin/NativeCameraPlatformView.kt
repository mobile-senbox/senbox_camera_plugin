package com.example.senbox_camera_plugin

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import android.util.Log
import android.view.Gravity
import android.view.OrientationEventListener
import android.view.Surface
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import android.util.Rational
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.ViewPort
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
import androidx.exifinterface.media.ExifInterface
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
    private var lastCaptureDebugInfo: Map<String, Any?>? = null
    private var currentDeviceRotation = Surface.ROTATION_0
    private val orientationListener = object : OrientationEventListener(context.applicationContext) {
        override fun onOrientationChanged(orientation: Int) {
            if (orientation == ORIENTATION_UNKNOWN) {
                return
            }
            currentDeviceRotation = snapOrientationToSurfaceRotation(orientation)
            updateCaptureRotation()
        }
    }
    private val canDetectDeviceOrientation = orientationListener.canDetectOrientation()

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

        if (canDetectDeviceOrientation) {
            currentDeviceRotation = currentDisplayRotation()
            orientationListener.enable()
        }

        plugin.setActiveCameraView(this)
        startWhenReady()
    }

    override fun getView(): View = container

    override fun dispose() {
        isDisposed = true
        orientationListener.disable()
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
        val baseRotation = currentBaseCaptureRotation()
        val targetRotation = desiredStillCaptureRotation()
        val displayRotation = currentDisplayRotation()
        imageCapture.targetRotation = targetRotation

        imageCapture.takePicture(
            outputOptions,
            ContextCompat.getMainExecutor(host.first),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                    val fileToProcess = outputFile
                    Thread {
                        val finalExifOrientation = rotateImageIfRequired(fileToProcess)
                        host.first.runOnUiThread {
                            if (isDisposed) return@runOnUiThread
                            lastCaptureDebugInfo = buildCaptureDebugInfo(
                                outputFile = fileToProcess,
                                baseRotation = baseRotation,
                                displayRotation = displayRotation,
                                targetRotation = targetRotation,
                                outputExifOrientation = finalExifOrientation
                            )
                            result.success(fileToProcess.absolutePath)
                        }
                    }.start()
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

        val activity = host.first
        if (!hasAudioPermission(activity)) {
            result.error(
                "AUDIO_PERMISSION_REQUIRED",
                "Microphone permission is required. Call requestAudioPermission() before startVideoRecording().",
                null
            )
            return
        }

        val targetRotation = desiredVideoCaptureRotation()
        videoCapture.targetRotation = targetRotation
        val outputFile = createMediaFile("mp4")
        currentVideoPath = outputFile.absolutePath
        val outputOptions = FileOutputOptions.Builder(outputFile).build()

        try {
            val pendingRecording = videoCapture.output
                .prepareRecording(activity, outputOptions)
                .withAudioEnabled()
            activeRecording = pendingRecording.start(ContextCompat.getMainExecutor(activity)) { event ->
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

    fun getLastCaptureDebugInfo(): Map<String, Any?>? = lastCaptureDebugInfo

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
                        .setTargetRotation(desiredStillCaptureRotation())
                        .build()

                    val recorder = Recorder.Builder()
                        .setQualitySelector(
                            QualitySelector.from(
                                Quality.HD,
                                FallbackStrategy.higherQualityOrLowerThan(Quality.SD)
                            )
                        )
                        .build()
                    val videoCapture = VideoCapture.withOutput(recorder).apply {
                        targetRotation = desiredVideoCaptureRotation()
                    }

                    provider.unbindAll()
                    boundCamera = null
                    previewUseCase = preview
                    imageCaptureUseCase = imageCapture
                    videoCaptureUseCase = videoCapture

                    val useCaseGroupBuilder = UseCaseGroup.Builder()
                        .addUseCase(preview)
                        .addUseCase(imageCapture)
                        .addUseCase(videoCapture)

                    val viewPort = previewView.viewPort ?: if (previewView.width > 0 && previewView.height > 0) {
                        ViewPort.Builder(
                            Rational(previewView.width, previewView.height),
                            currentDisplayRotation()
                        ).setScaleType(ViewPort.FILL_CENTER).build()
                    } else null

                    if (viewPort != null) {
                        useCaseGroupBuilder.setViewPort(viewPort)
                    }

                    val camera = provider.bindToLifecycle(
                        lifecycleOwner,
                        selector,
                        useCaseGroupBuilder.build()
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

    private fun hasAudioPermission(activity: Activity): Boolean {
        return ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.RECORD_AUDIO
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

    private fun rotateImageIfRequired(imageFile: File): Int {
        val exif = try {
            ExifInterface(imageFile.absolutePath)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read EXIF: ${e.message}", e)
            return ExifInterface.ORIENTATION_NORMAL
        }
        val orientation = exif.getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL
        )

        val degrees = when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90
            ExifInterface.ORIENTATION_ROTATE_180 -> 180
            ExifInterface.ORIENTATION_ROTATE_270 -> 270
            else -> 0
        }

        if (degrees == 0) {
            return orientation
        }

        try {
            val bitmap = BitmapFactory.decodeFile(imageFile.absolutePath) ?: return orientation
            val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
            val rotatedBitmap = Bitmap.createBitmap(
                bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true
            )
            
            imageFile.outputStream().use { out ->
                rotatedBitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)
            }
            
            if (bitmap != rotatedBitmap) {
                bitmap.recycle()
            }
            rotatedBitmap.recycle()

            val newExif = ExifInterface(imageFile.absolutePath)
            newExif.setAttribute(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL.toString()
            )
            newExif.saveAttributes()
            return ExifInterface.ORIENTATION_NORMAL
        } catch (e: OutOfMemoryError) {
            Log.e(TAG, "OutOfMemoryError when rotating image", e)
            System.gc()
        } catch (e: Exception) {
            Log.e(TAG, "Error rotating image: ${e.message}", e)
        }
        return orientation
    }

    private fun createMediaFile(extension: String): File {
        val outputDir = File(rootContext.cacheDir, "senbox_camera_plugin")
        if (!outputDir.exists()) {
            outputDir.mkdirs()
        }
        return File.createTempFile("sbx_${System.currentTimeMillis()}_", ".$extension", outputDir)
    }

    private fun currentBaseCaptureRotation(): Int {
        return if (canDetectDeviceOrientation) {
            currentDeviceRotation
        } else {
            currentDisplayRotation()
        }
    }

    private fun desiredStillCaptureRotation(): Int {
        return currentBaseCaptureRotation()
    }

    private fun desiredVideoCaptureRotation(baseRotation: Int = currentBaseCaptureRotation()): Int {
        return baseRotation
    }

    private fun updateCaptureRotation() {
        try {
            videoCaptureUseCase?.targetRotation = desiredVideoCaptureRotation()
            imageCaptureUseCase?.targetRotation = desiredStillCaptureRotation()
        } catch (_: Exception) {
        }
    }

    private fun currentDisplayRotation(): Int {
        return previewView.display?.rotation ?: Surface.ROTATION_0
    }

    private fun snapOrientationToSurfaceRotation(orientation: Int): Int {
        return when (orientation) {
            in 45..134 -> Surface.ROTATION_270
            in 135..224 -> Surface.ROTATION_180
            in 225..314 -> Surface.ROTATION_90
            else -> Surface.ROTATION_0
        }
    }

    private fun buildCaptureDebugInfo(
        outputFile: File,
        baseRotation: Int,
        displayRotation: Int,
        targetRotation: Int,
        outputExifOrientation: Int
    ): Map<String, Any?> {
        val normalizedToPortraitUp = targetRotation == Surface.ROTATION_0
        val usesExifOrientation = outputExifOrientation != ExifInterface.ORIENTATION_NORMAL

        return mapOf(
            "filePath" to outputFile.absolutePath,
            "rotationSource" to if (canDetectDeviceOrientation) "device" else "display",
            "deviceRotation" to currentDeviceRotation,
            "deviceRotationLabel" to surfaceRotationLabel(currentDeviceRotation),
            "displayRotation" to displayRotation,
            "displayRotationLabel" to surfaceRotationLabel(displayRotation),
            "baseRotation" to baseRotation,
            "baseRotationLabel" to surfaceRotationLabel(baseRotation),
            "targetRotation" to targetRotation,
            "targetRotationLabel" to surfaceRotationLabel(targetRotation),
            "normalizedToPortraitUp" to normalizedToPortraitUp,
            "usesExifOrientation" to usesExifOrientation,
            "outputExifOrientation" to outputExifOrientation,
            "outputExifOrientationLabel" to exifOrientationLabel(outputExifOrientation)
        )
    }

    private fun surfaceRotationLabel(rotation: Int): String {
        return when (rotation) {
            Surface.ROTATION_0 -> "portraitUp"
            Surface.ROTATION_90 -> "landscapeRight"
            Surface.ROTATION_180 -> "portraitDown"
            Surface.ROTATION_270 -> "landscapeLeft"
            else -> "unknown"
        }
    }

    private fun exifOrientationLabel(orientation: Int): String {
        return when (orientation) {
            ExifInterface.ORIENTATION_NORMAL -> "normal"
            ExifInterface.ORIENTATION_ROTATE_90 -> "rotate90"
            ExifInterface.ORIENTATION_ROTATE_180 -> "rotate180"
            ExifInterface.ORIENTATION_ROTATE_270 -> "rotate270"
            else -> "undefined"
        }
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
