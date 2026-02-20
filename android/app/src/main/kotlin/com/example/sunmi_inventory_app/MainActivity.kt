package com.example.sunmi_inventory_app

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.IBinder
import android.os.RemoteException
import android.provider.MediaStore
import android.util.Log
import androidx.core.content.FileProvider
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatWriter
import com.google.zxing.common.BitMatrix
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import woyou.aidlservice.jiuiv5.ICallback
import woyou.aidlservice.jiuiv5.IWoyouService

class MainActivity : FlutterActivity() {
    private val channelName = "pos_steward_printer"
    private val cameraChannelName = "pos_steward_camera"
    private var woyouService: IWoyouService? = null
    private var isServiceBound: Boolean = false
    private var pendingCameraResult: MethodChannel.Result? = null
    private var pendingCameraPath: String? = null

    private val printerCallback = object : ICallback.Stub() {
        override fun onRunResult(isSuccess: Boolean) {
            Log.i(TAG, "printer callback onRunResult=$isSuccess")
        }

        override fun onReturnString(result: String?) {
            Log.i(TAG, "printer callback onReturnString=$result")
        }

        override fun onRaiseException(code: Int, msg: String?) {
            Log.e(TAG, "printer callback onRaiseException code=$code msg=$msg")
        }

        override fun onPrintResult(code: Int, msg: String?) {
            Log.i(TAG, "printer callback onPrintResult code=$code msg=$msg")
        }
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            woyouService = IWoyouService.Stub.asInterface(service)
            isServiceBound = true
            Log.i(TAG, "IWoyouService connected")
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            woyouService = null
            isServiceBound = false
            Log.w(TAG, "IWoyouService disconnected")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindAndGetStatus" -> {
                        try {
                            val bound = ensureServiceBound()
                            val status = safePrinterStatus()
                            result.success(
                                hashMapOf(
                                    "bound" to bound,
                                    "status" to status,
                                    "serviceVersion" to safeServiceVersion(),
                                ),
                            )
                        } catch (e: Exception) {
                            Log.e(TAG, "bindAndGetStatus failed", e)
                            result.error("BIND_STATUS_FAILED", e.message, null)
                        }
                    }

                    "printPayload" -> {
                        handlePrintPayload(call, result)
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, cameraChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "capturePhoto" -> handleCapturePhoto(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handlePrintPayload(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (!ensureServiceBound()) {
                result.error("BIND_FAILED", "Failed to bind printer service", null)
                return
            }

            val service = woyouService
            if (service == null) {
                result.error("NO_SERVICE", "Printer service is null", null)
                return
            }

            @Suppress("UNCHECKED_CAST")
            val lines = call.argument<List<String>>("lines") ?: emptyList()
            val barcode = call.argument<String>("barcode")
            val qrData = call.argument<String>("qrData")
            val alignment = call.argument<Int>("alignment") ?: 0
            val textSize = (call.argument<Number>("textSize") ?: 18).toFloat()
            val qrErrorLevel = (call.argument<Number>("qrErrorLevel") ?: 2).toInt().coerceIn(0, 3)
            val qrSizePx = (call.argument<Number>("qrSizePx") ?: 200).toInt().coerceIn(140, 300)
            val barcodeHeight = (call.argument<Number>("barcodeHeight") ?: 130).toInt().coerceIn(1, 255)
            val barcodeWidth = (call.argument<Number>("barcodeWidth") ?: 3).toInt().coerceIn(2, 6)
            val barcodeWidthPx = (call.argument<Number>("barcodeWidthPx") ?: 360).toInt().coerceIn(240, 380)
            val barcodeHeightPx = (call.argument<Number>("barcodeHeightPx") ?: 130).toInt().coerceIn(80, 180)
            val centerFirstLine = call.argument<Boolean>("centerFirstLine") ?: false
            val printTextBelowCodes = call.argument<Boolean>("printTextBelowCodes") ?: true

            service.printerInit(printerCallback)
            // Reset printer mode and explicitly disable reverse/inverse colors.
            service.sendRAWData(raw(0x1B, 0x40), printerCallback)
            service.sendRAWData(raw(0x1D, 0x42, 0x00), printerCallback)
            service.sendRAWData(raw(0x1B, 0x45, 0x00), printerCallback)
            service.sendRAWData(raw(0x1B, 0x21, 0x00), printerCallback)
            service.sendRAWData(raw(0x1D, 0x21, 0x00), printerCallback)

            service.setFontSize(textSize, printerCallback)
            for ((index, line) in lines.withIndex()) {
                val lineAlignment = if (centerFirstLine && index == 0) 1 else alignment
                service.setAlignment(lineAlignment, printerCallback)
                service.sendRAWData(raw(0x1D, 0x42, 0x00), printerCallback)
                service.printTextWithFont("$line\n", "", textSize, printerCallback)
            }
            service.setAlignment(alignment, printerCallback)

            if (!barcode.isNullOrBlank() || !qrData.isNullOrBlank()) {
                service.lineWrap(1, printerCallback)
                service.setAlignment(1, printerCallback) // center
            }

            if (!barcode.isNullOrBlank()) {
                val barcodeSymbology = chooseSunmiBarcodeSymbology(barcode.trim())
                var printedByCommand = false
                try {
                    service.printBarCode(
                        barcode.trim(),
                        barcodeSymbology,
                        barcodeHeight,
                        barcodeWidth,
                        0,
                        printerCallback,
                    )
                    printedByCommand = true
                } catch (e: Exception) {
                    Log.w(TAG, "printBarCode command failed, fallback to bitmap", e)
                }
                if (!printedByCommand) {
                    val barcodeBitmap = createBarcodeBitmap(
                        data = barcode,
                        widthPx = barcodeWidthPx,
                        heightPx = barcodeHeightPx,
                    )
                    service.printBitmap(barcodeBitmap, printerCallback)
                }
                service.lineWrap(1, printerCallback)
                if (printTextBelowCodes) {
                    service.printTextWithFont("$barcode\n", "", 16f, printerCallback)
                }
            }

            if (!qrData.isNullOrBlank()) {
                service.lineWrap(1, printerCallback)
                val qrBitmap = createQrBitmap(
                    data = qrData,
                    sizePx = qrSizePx,
                    errorLevel = qrErrorLevel,
                )
                service.printBitmap(qrBitmap, printerCallback)
                service.lineWrap(1, printerCallback)
                if (printTextBelowCodes) {
                    service.printTextWithFont("$qrData\n", "", 14f, printerCallback)
                }
            }

            service.lineWrap(2, printerCallback)
            try {
                service.cutPaper(printerCallback)
            } catch (_: Exception) {
                // Some devices do not support cut.
            }

            result.success(
                hashMapOf(
                    "ok" to true,
                    "status" to safePrinterStatus(),
                ),
            )
        } catch (e: RemoteException) {
            Log.e(TAG, "printPayload remote error", e)
            result.error("PRINT_REMOTE_ERROR", e.message, null)
        } catch (e: Exception) {
            Log.e(TAG, "printPayload failed", e)
            result.error("PRINT_FAILED", e.message, null)
        }
    }

    private fun handleCapturePhoto(result: MethodChannel.Result) {
        if (pendingCameraResult != null) {
            result.error("CAMERA_BUSY", "カメラ起動中です。しばらく待ってください。", null)
            return
        }

        try {
            val captureIntent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
            if (captureIntent.resolveActivity(packageManager) == null) {
                result.error("NO_CAMERA_APP", "カメラアプリが見つかりません。", null)
                return
            }

            val photoFile = createCaptureImageFile()
            val authority = "${applicationContext.packageName}.fileprovider"
            val photoUri: Uri = FileProvider.getUriForFile(this, authority, photoFile)

            pendingCameraPath = photoFile.absolutePath
            pendingCameraResult = result

            captureIntent.putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
            captureIntent.addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            startActivityForResult(captureIntent, CAPTURE_PHOTO_REQUEST_CODE)
        } catch (e: Exception) {
            pendingCameraPath = null
            pendingCameraResult = null
            Log.e(TAG, "Failed to start camera capture", e)
            result.error("CAPTURE_START_FAILED", e.message, null)
        }
    }

    private fun createCaptureImageFile(): File {
        val baseDir = File(filesDir, "product_images")
        if (!baseDir.exists()) {
            baseDir.mkdirs()
        }
        val timeStamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val fileName = "product_${timeStamp}_${System.currentTimeMillis()}.jpg"
        return File(baseDir, fileName)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CAPTURE_PHOTO_REQUEST_CODE) {
            return
        }

        val callback = pendingCameraResult
        val photoPath = pendingCameraPath
        pendingCameraResult = null
        pendingCameraPath = null

        if (callback == null) {
            return
        }

        if (resultCode == Activity.RESULT_OK && photoPath != null && File(photoPath).exists()) {
            callback.success(photoPath)
            return
        }

        if (photoPath != null) {
            try {
                File(photoPath).delete()
            } catch (_: Exception) {
                // Ignore cleanup errors.
            }
        }
        callback.success(null)
    }

    private fun raw(vararg bytes: Int): ByteArray {
        return ByteArray(bytes.size) { index -> bytes[index].toByte() }
    }

    private fun createQrBitmap(data: String, sizePx: Int, errorLevel: Int): Bitmap {
        val ecLevel = when (errorLevel) {
            0 -> ErrorCorrectionLevel.L
            1 -> ErrorCorrectionLevel.M
            2 -> ErrorCorrectionLevel.Q
            else -> ErrorCorrectionLevel.H
        }
        val hints = hashMapOf<EncodeHintType, Any>(
            EncodeHintType.CHARACTER_SET to "UTF-8",
            EncodeHintType.ERROR_CORRECTION to ecLevel,
            EncodeHintType.MARGIN to 2,
        )
        val matrix = MultiFormatWriter().encode(
            data,
            BarcodeFormat.QR_CODE,
            sizePx,
            sizePx,
            hints,
        )
        return bitMatrixToBitmap(matrix)
    }

    private fun createBarcodeBitmap(data: String, widthPx: Int, heightPx: Int): Bitmap {
        val normalized = data.trim()
        val preferredFormat = chooseLinearBarcodeFormat(normalized)
        val hints = hashMapOf<EncodeHintType, Any>(
            EncodeHintType.MARGIN to 16,
        )
        return try {
            val matrix = MultiFormatWriter().encode(
                normalized,
                preferredFormat,
                widthPx,
                heightPx,
                hints,
            )
            bitMatrixToBitmap(matrix)
        } catch (e: Exception) {
            if (preferredFormat != BarcodeFormat.CODE_128) {
                Log.w(
                    TAG,
                    "Barcode encode failed for format=$preferredFormat data=$normalized. Fallback to CODE_128.",
                    e,
                )
                val fallbackMatrix = MultiFormatWriter().encode(
                    normalized,
                    BarcodeFormat.CODE_128,
                    widthPx,
                    heightPx,
                    hints,
                )
                return bitMatrixToBitmap(fallbackMatrix)
            }
            throw e
        }
    }

    private fun chooseLinearBarcodeFormat(data: String): BarcodeFormat {
        if (data.isEmpty() || !data.all { it.isDigit() }) {
            return BarcodeFormat.CODE_128
        }

        return when (data.length) {
            13 -> BarcodeFormat.EAN_13
            12 -> BarcodeFormat.UPC_A
            8 -> BarcodeFormat.EAN_8
            else -> BarcodeFormat.CODE_128
        }
    }

    private fun chooseSunmiBarcodeSymbology(data: String): Int {
        if (data.isEmpty() || !data.all { it.isDigit() }) {
            return 8 // CODE128
        }

        return when (data.length) {
            13 -> 2 // JAN13 (EAN-13)
            12 -> 0 // UPC-A
            8 -> 3 // JAN8 (EAN-8)
            else -> 8 // CODE128
        }
    }

    private fun bitMatrixToBitmap(matrix: BitMatrix): Bitmap {
        val width = matrix.width
        val height = matrix.height
        val pixels = IntArray(width * height)
        for (y in 0 until height) {
            val offset = y * width
            for (x in 0 until width) {
                pixels[offset + x] = if (matrix[x, y]) Color.BLACK else Color.WHITE
            }
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }

    private fun ensureServiceBound(): Boolean {
        if (woyouService != null && isServiceBound) {
            return true
        }

        val intent = Intent().apply {
            setPackage("woyou.aidlservice.jiuiv5")
            action = "woyou.aidlservice.jiuiv5.IWoyouService"
        }

        val bound = applicationContext.bindService(
            intent,
            serviceConnection,
            Context.BIND_AUTO_CREATE,
        )
        if (!bound) {
            Log.e(TAG, "bindService returned false")
            isServiceBound = false
            woyouService = null
            return false
        }
        val ready = woyouService != null && isServiceBound
        Log.i(TAG, "ensureServiceBound ready=$ready (bind requested)")
        return ready
    }

    private fun safePrinterStatus(): Int {
        return try {
            woyouService?.updatePrinterState() ?: -1
        } catch (_: Exception) {
            -1
        }
    }

    private fun safeServiceVersion(): String {
        return try {
            woyouService?.serviceVersion ?: ""
        } catch (_: Exception) {
            ""
        }
    }

    override fun onDestroy() {
        if (isServiceBound) {
            try {
                applicationContext.unbindService(serviceConnection)
            } catch (_: Exception) {
                // Ignore unbind errors.
            }
        }
        isServiceBound = false
        woyouService = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "PosStewardPrinter"
        private const val CAPTURE_PHOTO_REQUEST_CODE = 40231
    }
}
