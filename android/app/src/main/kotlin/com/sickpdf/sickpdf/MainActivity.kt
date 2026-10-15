package com.sickpdf.sickpdf

import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val protectWorker = Executors.newSingleThreadExecutor()
    private val unlockWorker = Executors.newSingleThreadExecutor()
    private val watermarkWorker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PDFBoxResourceLoader.init(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sickpdf/protect")
            .setMethodCallHandler { call, result ->
                if (call.method != "protect") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val password = call.argument<String>("password")
                if (bytes == null || password == null) {
                    result.error("invalid_input", "Invalid protection request.", null)
                    return@setMethodCallHandler
                }
                protectWorker.execute {
                    try {
                        val output = PdfProtector.protect(bytes, password)
                        runOnUiThread { result.success(output) }
                    } catch (_: InvalidPasswordException) {
                        runOnUiThread { result.error("locked_pdf", "Use an unlocked PDF.", null) }
                    } catch (_: Exception) {
                        runOnUiThread { result.error("protect_failed", "Could not protect this PDF.", null) }
                    } catch (_: OutOfMemoryError) {
                        runOnUiThread { result.error("too_large", "Not enough memory. Try a smaller PDF.", null) }
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sickpdf/unlock")
            .setMethodCallHandler { call, result ->
                if (call.method != "unlock") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val password = call.argument<String>("password")
                if (bytes == null || password == null || password.isEmpty()) {
                    result.error("invalid_input", "Invalid unlock request.", null)
                    return@setMethodCallHandler
                }
                unlockWorker.execute {
                    try {
                        val output = PdfUnlocker.unlock(bytes, password)
                        runOnUiThread { result.success(output) }
                    } catch (_: InvalidPasswordException) {
                        runOnUiThread { result.error("wrong_password", "Incorrect PDF password.", null) }
                    } catch (_: Exception) {
                        runOnUiThread { result.error("unlock_failed", "Could not unlock this PDF.", null) }
                    } catch (_: OutOfMemoryError) {
                        runOnUiThread { result.error("too_large", "Not enough memory. Try a smaller PDF.", null) }
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sickpdf/watermark")
            .setMethodCallHandler { call, result ->
                if (call.method != "watermark") { result.notImplemented(); return@setMethodCallHandler }
                val bytes = call.argument<ByteArray>("bytes")
                val text = call.argument<String>("text")
                val fontSize = call.argument<Double>("fontSize")?.toFloat()
                val opacity = call.argument<Double>("opacity")?.toFloat()
                val position = call.argument<String>("position")
                val rotation = call.argument<String>("rotation")
                val pages = call.argument<List<Int>>("pages")
                if (bytes == null || text == null || fontSize == null || opacity == null || position == null || rotation == null) {
                    result.error("invalid_input", "Invalid watermark request.", null); return@setMethodCallHandler
                }
                watermarkWorker.execute {
                    try { runOnUiThread { result.success(PdfWatermarker.apply(bytes, text, fontSize, opacity, position, rotation, pages)) } }
                    catch (error: IllegalArgumentException) { runOnUiThread { result.error("invalid_input", error.message, null) } }
                    catch (_: OutOfMemoryError) { runOnUiThread { result.error("too_large", "Not enough memory. Try a smaller PDF.", null) } }
                    catch (_: Exception) { runOnUiThread { result.error("watermark_failed", "Could not watermark this PDF. It may be encrypted, damaged, signed, or unsupported.", null) } }
                }
            }
    }

    override fun onDestroy() {
        protectWorker.shutdown()
        unlockWorker.shutdown()
        watermarkWorker.shutdown()
        super.onDestroy()
    }
}
