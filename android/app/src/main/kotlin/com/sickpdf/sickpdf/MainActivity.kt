package com.sickpdf.sickpdf

import android.content.Intent
import androidx.core.content.FileProvider
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val protectWorker = Executors.newSingleThreadExecutor()
    private val unlockWorker = Executors.newSingleThreadExecutor()
    private val watermarkWorker = Executors.newSingleThreadExecutor()
    private val pageNumberWorker = Executors.newSingleThreadExecutor()
    private val signWorker = Executors.newSingleThreadExecutor()
    private val addTextWorker = Executors.newSingleThreadExecutor()
    private val imageWorker = Executors.newSingleThreadExecutor()

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sickpdf/sign")
            .setMethodCallHandler { call, result ->
                if (call.method != "sign") { result.notImplemented(); return@setMethodCallHandler }
                val bytes = call.argument<ByteArray>("bytes")
                val signature = call.argument<ByteArray>("signature")
                val pageIndex = call.argument<Int>("pageIndex")
                val position = call.argument<String>("position")
                val widthFraction = call.argument<Double>("widthFraction")?.toFloat()
                val heightFraction = call.argument<Double>("heightFraction")?.toFloat()
                val offsetXFraction = call.argument<Double>("offsetXFraction")?.toFloat()
                val offsetYFraction = call.argument<Double>("offsetYFraction")?.toFloat()
                val opacity = call.argument<Double>("opacity")?.toFloat()
                if (bytes == null || signature == null || pageIndex == null || position == null ||
                    widthFraction == null || heightFraction == null || offsetXFraction == null ||
                    offsetYFraction == null || opacity == null) {
                    result.error("invalid_input", "Invalid signature request.", null); return@setMethodCallHandler
                }
                signWorker.execute {
                    try { runOnUiThread { result.success(PdfSigner.apply(bytes, signature, pageIndex, position, widthFraction, heightFraction, offsetXFraction, offsetYFraction, opacity)) } }
                    catch (error: IllegalArgumentException) { runOnUiThread { result.error("invalid_input", error.message, null) } }
                    catch (_: OutOfMemoryError) { runOnUiThread { result.error("too_large", "Not enough memory. Try a smaller PDF.", null) } }
                    catch (_: Exception) { runOnUiThread { result.error("sign_failed", "Could not sign this PDF. It may be encrypted, damaged, signed, or unsupported.", null) } }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sickpdf/addtext")
            .setMethodCallHandler { call, result ->
                if (call.method != "addText") { result.notImplemented(); return@setMethodCallHandler }
                val bytes = call.argument<ByteArray>("bytes")
                val text = call.argument<String>("text")
                val fontSize = call.argument<Double>("fontSize")?.toFloat()
                val colorR = call.argument<Double>("colorR")?.toFloat()
                val colorG = call.argument<Double>("colorG")?.toFloat()
                val colorB = call.argument<Double>("colorB")?.toFloat()
                val alignment = call.argument<String>("alignment")
                val vertical = call.argument<String>("vertical")
                val pages = call.argument<List<Int>>("pages")
                if (bytes == null || text == null || fontSize == null || colorR == null || colorG == null || colorB == null || alignment == null || vertical == null) {
                    result.error("invalid_input", "Invalid text request.", null); return@setMethodCallHandler
                }
                addTextWorker.execute {
                    try { runOnUiThread { result.success(PdfTextAdder.apply(bytes, text, fontSize, colorR, colorG, colorB, alignment, vertical, pages)) } }
                    catch (error: IllegalArgumentException) { runOnUiThread { result.error("invalid_input", error.message, null) } }
                    catch (_: OutOfMemoryError) { runOnUiThread { result.error("too_large", "Not enough memory. Try a smaller PDF.", null) } }
                    catch (_: Exception) { runOnUiThread { result.error("addtext_failed", "Could not add text to this PDF. It may be encrypted, damaged, signed, or unsupported.", null) } }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sickpdf/pagenumbers")
            .setMethodCallHandler { call, result ->
                if (call.method != "addPageNumbers") { result.notImplemented(); return@setMethodCallHandler }
                val bytes = call.argument<ByteArray>("bytes")
                val format = call.argument<String>("format")
                val position = call.argument<String>("position")
                val startNumber = call.argument<Int>("startNumber")
                val firstPage = call.argument<Int>("firstPage")
                val lastPage = call.argument<Int>("lastPage")
                val fontSize = call.argument<Double>("fontSize")?.toFloat()
                val colorR = call.argument<Double>("colorR")?.toFloat()
                val colorG = call.argument<Double>("colorG")?.toFloat()
                val colorB = call.argument<Double>("colorB")?.toFloat()
                if (bytes == null || format == null || position == null || startNumber == null || firstPage == null || lastPage == null || fontSize == null || colorR == null || colorG == null || colorB == null) {
                    result.error("invalid_input", "Invalid page numbering request.", null); return@setMethodCallHandler
                }
                pageNumberWorker.execute {
                    try { runOnUiThread { result.success(PdfPageNumberer.apply(bytes, format, position, startNumber, firstPage, lastPage, fontSize, colorR, colorG, colorB)) } }
                    catch (error: IllegalArgumentException) { runOnUiThread { result.error("invalid_input", error.message, null) } }
                    catch (_: OutOfMemoryError) { runOnUiThread { result.error("too_large", "Not enough memory. Try a smaller PDF.", null) } }
                    catch (_: Exception) { runOnUiThread { result.error("pagenumber_failed", "Could not add page numbers. It may be encrypted, damaged, signed, or unsupported.", null) } }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sickpdf/images")
            .setMethodCallHandler { call, result ->
                if (call.method != "convert") { result.notImplemented(); return@setMethodCallHandler }
                val images = call.argument<List<ByteArray>>("images")
                val pageSize = call.argument<String>("pageSize")
                val margin = call.argument<Double>("margin")?.toFloat()
                val fit = call.argument<String>("fit")
                val squareSide = call.argument<Double>("squareSide")?.toFloat()
                if (images == null || images.isEmpty() || pageSize == null || margin == null || fit == null || squareSide == null) {
                    result.error("invalid_input", "Invalid image conversion request.", null); return@setMethodCallHandler
                }
                imageWorker.execute {
                    try { runOnUiThread { result.success(PdfImageConverter.convert(images, pageSize, margin, fit, squareSide)) } }
                    catch (error: IllegalArgumentException) { runOnUiThread { result.error("invalid_input", error.message, null) } }
                    catch (_: OutOfMemoryError) { runOnUiThread { result.error("too_large", "Not enough memory. Try fewer or smaller images.", null) } }
                    catch (_: Exception) { runOnUiThread { result.error("convert_failed", "Could not create the PDF from these images. Try removing the affected image.", null) } }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sickpdf/share")
            .setMethodCallHandler { call, result ->
                if (call.method != "share") { result.notImplemented(); return@setMethodCallHandler }
                val bytes = call.argument<ByteArray>("bytes")
                val fileName = call.argument<String>("fileName")
                if (bytes == null || bytes.isEmpty() || fileName.isNullOrBlank()) {
                    result.error("invalid_input", "Nothing to share.", null); return@setMethodCallHandler
                }
                try {
                    // Only PDF and plain text outputs exist today, so the
                    // extension and the shared mime type follow the name.
                    val safeName = File(fileName).name.let {
                        when {
                            it.lowercase().endsWith(".pdf") -> it
                            it.lowercase().endsWith(".txt") -> it
                            else -> "$it.pdf"
                        }
                    }
                    val mimeType = if (safeName.lowercase().endsWith(".txt")) {
                        "text/plain"
                    } else {
                        "application/pdf"
                    }
                    val directory = File(cacheDir, "shared").apply { mkdirs() }
                    val target = File(directory, safeName)
                    FileOutputStream(target).use { it.write(bytes) }
                    val uri = FileProvider.getUriForFile(
                        this,
                        "$packageName.fileprovider",
                        target,
                    )
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = mimeType
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    runOnUiThread {
                        startActivity(Intent.createChooser(intent, "Share file"))
                        result.success(null)
                    }
                } catch (_: Exception) {
                    runOnUiThread { result.error("share_failed", "Could not share this file.", null) }
                }
            }
    }

    override fun onDestroy() {
        protectWorker.shutdown()
        unlockWorker.shutdown()
        watermarkWorker.shutdown()
        pageNumberWorker.shutdown()
        signWorker.shutdown()
        addTextWorker.shutdown()
        imageWorker.shutdown()
        super.onDestroy()
    }
}
