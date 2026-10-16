package com.sickpdf.sickpdf

import android.graphics.BitmapFactory
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import com.tom_roush.pdfbox.util.Matrix
import java.io.ByteArrayOutputStream
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Builds a multi-page PDF with exactly one image per page, in the given order.
 *
 * Each image is decoded once, then drawn immediately, so peak memory stays
 * close to a single decoded bitmap regardless of how many images are selected.
 * JPEG images are embedded directly (no re-encode, no quality loss); other
 * formats (PNG, ...) are embedded through PDFBox's lossless path.
 *
 * EXIF orientation is respected: the effective width/height and the drawing
 * rotation are derived from the EXIF orientation tag so portrait phone photos
 * are not rotated or cropped. Page geometry (contain/cover/stretch, margins,
 * page size) is computed here from the already-validated Dart options.
 */
internal object PdfImageConverter {

    private const val A4_PORTRAIT_W = 595.276f
    private const val A4_PORTRAIT_H = 841.89f
    private const val LETTER_PORTRAIT_W = 612f
    private const val LETTER_PORTRAIT_H = 792f

    // EXIF orientation values (subset used for rotation).
    private const val ORIENTATION_UNDEFINED = 0
    private const val ORIENTATION_NORMAL = 1
    private const val ORIENTATION_ROTATE_90 = 6
    private const val ORIENTATION_ROTATE_180 = 3
    private const val ORIENTATION_ROTATE_270 = 8
    private const val ORIENTATION_MIRROR_H = 2
    private const val ORIENTATION_TRANSPOSE = 5
    private const val ORIENTATION_TRANSVERSE = 7

    fun convert(
        images: List<ByteArray>,
        pageSize: String,
        marginPoints: Float,
        fit: String,
        squareSide: Float,
    ): ByteArray {
        require(images.isNotEmpty()) { "Select at least one image to convert." }
        require(marginPoints >= 0f) { "Margin must not be negative." }
        require(pageSize != "square" || squareSide > 0f) {
            "Square page side must be greater than zero."
        }
        images.forEachIndexed { index, bytes ->
            require(bytes.isNotEmpty()) {
                "Image ${index + 1} is empty or could not be read."
            }
        }

        PDDocument().use { document ->
            images.forEach { bytes ->
                addImagePage(document, bytes, pageSize, marginPoints, fit, squareSide)
            }
            val output = ByteArrayOutputStream()
            document.save(output)
            return output.toByteArray().also { check(it.isNotEmpty()) }
        }
    }

    private fun addImagePage(
        document: PDDocument,
        bytes: ByteArray,
        pageSize: String,
        marginPoints: Float,
        fit: String,
        squareSide: Float,
    ) {
        val meta = readImageMeta(bytes)
        val orientation = meta.orientation
        val swaps = orientation == ORIENTATION_ROTATE_90 ||
            orientation == ORIENTATION_ROTATE_270 ||
            orientation == ORIENTATION_TRANSPOSE ||
            orientation == ORIENTATION_TRANSVERSE
        val displayWidth = if (swaps) meta.height else meta.width
        val displayHeight = if (swaps) meta.width else meta.height

        val box = pageBox(pageSize, displayWidth, displayHeight, squareSide)
        val page = PDPage(PDRectangle(box.first, box.second))
        document.addPage(page)

        val image = PDImageXObject.createFromByteArray(document, bytes, "image")

        val margin = min(marginPoints, min(box.first, box.second) / 2f)
        val contentW = max(1f, box.first - margin * 2f)
        val contentH = max(1f, box.second - margin * 2f)
        val rect = fitRect(
            contentW,
            contentH,
            displayWidth,
            displayHeight,
            fit,
            margin,
        )

        PDPageContentStream(document, page).use { stream ->
            val rotation = rotationDegrees(orientation)
            val mirrored = orientation == ORIENTATION_MIRROR_H ||
                orientation == ORIENTATION_TRANSPOSE ||
                orientation == ORIENTATION_TRANSVERSE
            if (rotation == 0f && !mirrored) {
                stream.drawImage(image, rect[0], rect[1], rect[2], rect[3])
            } else {
                // Rotate/mirror around the destination rectangle centre to bake
                // EXIF orientation into the page content.
                val centerX = rect[0] + rect[2] / 2f
                val centerY = rect[1] + rect[3] / 2f
                stream.saveGraphicsState()
                stream.transform(
                    transformMatrix(centerX, centerY, rotation, mirrored),
                )
                stream.drawImage(image, rect[0], rect[1], rect[2], rect[3])
                stream.restoreGraphicsState()
            }
        }
    }

    private class ImageMeta(val width: Int, val height: Int, val orientation: Int)

    /** Returns dimensions and EXIF orientation without a full pixel decode. */
    private fun readImageMeta(bytes: ByteArray): ImageMeta {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) {
            "One of the images could not be decoded. It may be corrupted or unsupported."
        }
        val orientation = readExifOrientation(bytes) ?: ORIENTATION_NORMAL
        return ImageMeta(bounds.outWidth, bounds.outHeight, orientation)
    }

    /**
     * Minimal, dependency-free JPEG EXIF orientation reader. Returns null for
     * non-JPEG data (PNG has no EXIF orientation), so callers keep the default.
     */
    private fun readExifOrientation(bytes: ByteArray): Int? {
        if (bytes.size < 4 ||
            (bytes[0].toInt() and 0xFF) != 0xFF ||
            (bytes[1].toInt() and 0xFF) != 0xD8
        ) {
            return null // Not a JPEG (e.g. PNG): no EXIF orientation.
        }
        var offset = 2
        while (offset + 4 <= bytes.size) {
            if ((bytes[offset].toInt() and 0xFF) != 0xFF) {
                offset++
                continue
            }
            val marker = bytes[offset + 1].toInt() and 0xFF
            if (marker == 0xD8 || marker == 0x01 || marker in 0xD0..0xD7) {
                offset += 2
                continue
            }
            if (marker == 0xDA || marker == 0xD9) return null // Start of scan/EOI.
            val segmentLength =
                ((bytes[offset + 2].toInt() and 0xFF) shl 8) or
                    (bytes[offset + 3].toInt() and 0xFF)
            if (segmentLength < 2 || offset + 2 + segmentLength > bytes.size) {
                return null
            }
            if (marker == 0xE1) {
                val orientation = parseExifOrientation(bytes, offset + 4, segmentLength - 2)
                if (orientation != null) return orientation
            }
            offset += 2 + segmentLength
        }
        return null
    }

    private fun parseExifOrientation(bytes: ByteArray, start: Int, length: Int): Int? {
        val exifHeader = byteArrayOf(0x45, 0x78, 0x69, 0x66, 0x00, 0x00) // "Exif\0\0"
        if (length < exifHeader.size + 8) return null
        for (i in exifHeader.indices) {
            if (bytes[start + i] != exifHeader[i]) return null
        }
        val tiff = start + exifHeader.size
        val little = when {
            bytes[tiff].toInt() == 0x49 && bytes[tiff + 1].toInt() == 0x49 -> true
            bytes[tiff].toInt() == 0x4D && bytes[tiff + 1].toInt() == 0x4D -> false
            else -> return null
        }
        fun u16(offset: Int): Int {
            val a = bytes[offset].toInt() and 0xFF
            val b = bytes[offset + 1].toInt() and 0xFF
            return if (little) (b shl 8) or a else (a shl 8) or b
        }
        fun u32(offset: Int): Int {
            var value = 0
            for (i in 0..3) {
                val byte = bytes[offset + i].toInt() and 0xFF
                value = if (little) (value shl 8) or byte else value or (byte shl (8 * (3 - i)))
            }
            return value
        }
        if (u16(tiff + 2) != 0x002A) return null
        val ifd0 = tiff + u32(tiff + 4)
        if (ifd0 + 2 > bytes.size) return null
        val entries = u16(ifd0)
        for (i in 0 until entries) {
            val entry = ifd0 + 2 + i * 12
            if (entry + 12 > bytes.size) return null
            if (u16(entry) == 0x0112) { // Orientation tag.
                return u16(entry + 8)
            }
        }
        return null
    }

    private fun pageBox(
        pageSize: String,
        displayWidth: Int,
        displayHeight: Int,
        squareSide: Float,
    ): Pair<Float, Float> {
        val portrait = displayHeight >= displayWidth
        return when (pageSize) {
            "original" ->
                Pair(max(1f, displayWidth.toFloat()), max(1f, displayHeight.toFloat()))
            "letter" ->
                if (portrait) Pair(LETTER_PORTRAIT_W, LETTER_PORTRAIT_H)
                else Pair(LETTER_PORTRAIT_H, LETTER_PORTRAIT_W)
            "square" -> Pair(squareSide, squareSide)
            // "a4" is the default.
            else ->
                if (portrait) Pair(A4_PORTRAIT_W, A4_PORTRAIT_H)
                else Pair(A4_PORTRAIT_H, A4_PORTRAIT_W)
        }
    }

    /**
     * Returns [x, y, width, height] (PDF points, bottom-left origin) for the
     * image inside a [contentW] x [contentH] content box whose bottom-left sits
     * at ([margin], [margin]).
     */
    private fun fitRect(
        contentW: Float,
        contentH: Float,
        imageW: Int,
        imageH: Int,
        fit: String,
        margin: Float,
    ): FloatArray {
        val iw = max(1, imageW).toFloat()
        val ih = max(1, imageH).toFloat()
        val scaleX = contentW / iw
        val scaleY = contentH / ih
        val drawW: Float
        val drawH: Float
        when (fit) {
            "cover" -> {
                val scale = max(scaleX, scaleY)
                drawW = iw * scale
                drawH = ih * scale
            }
            "stretch" -> {
                drawW = contentW
                drawH = contentH
            }
            // "contain" is the default and never crops.
            else -> {
                val scale = min(scaleX, scaleY)
                drawW = iw * scale
                drawH = ih * scale
            }
        }
        val x = margin + (contentW - drawW) / 2f
        val y = margin + (contentH - drawH) / 2f
        return floatArrayOf(x, y, drawW, drawH)
    }

    private fun rotationDegrees(orientation: Int): Float = when (orientation) {
        ORIENTATION_ROTATE_90 -> 90f
        ORIENTATION_ROTATE_180 -> 180f
        ORIENTATION_ROTATE_270 -> 270f
        else -> 0f
    }

    /** PDF transform matrix; rotates by [degrees] about (cx, cy). */
    private fun transformMatrix(
        cx: Float,
        cy: Float,
        degrees: Float,
        mirrored: Boolean,
    ): Matrix {
        val radians = Math.toRadians(degrees.toDouble())
        val cosV = cos(radians).toFloat()
        val sinV = sin(radians).toFloat()
        val scaleX = if (mirrored) -1f else 1f
        val a = cosV * scaleX
        val b = sinV
        val c = -sinV * scaleX
        val d = cosV
        val e = cx - cx * a - cy * c
        val f = cy - cx * b - cy * d
        return Matrix(a, b, c, d, e, f)
    }
}
