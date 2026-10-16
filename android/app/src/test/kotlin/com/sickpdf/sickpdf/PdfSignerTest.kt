package com.sickpdf.sickpdf

import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.CRC32
import java.util.zip.Deflater

class PdfSignerTest {
    private fun source(pages: Int = 2): ByteArray = PDDocument().use { document ->
        repeat(pages) { index ->
            val page = PDPage(PDRectangle(300f + index, 400f))
            document.addPage(page)
            PDPageContentStream(document, page).use { stream ->
                stream.addRect(20f, 30f, 80f, 100f)
                stream.fill()
            }
        }
        ByteArrayOutputStream().use { document.save(it); it.toByteArray() }
    }

    /**
     * A hand-built 8x8 RGBA PNG with a transparent background. Assembled
     * without android.graphics.Bitmap so the fixture builds in plain JVM tests.
     */
    private fun signature(): ByteArray {
        val width = 8
        val height = 8
        val raw = ByteArrayOutputStream()
        for (y in 0 until height) {
            raw.write(0) // per-row filter byte
            for (x in 0 until width) {
                val opaque = x == y
                raw.write(0)
                raw.write(0)
                raw.write(0)
                raw.write(if (opaque) 255 else 0)
            }
        }
        val compressed = ByteArrayOutputStream()
        val deflater = Deflater()
        try {
            deflater.setInput(raw.toByteArray())
            deflater.finish()
            val buffer = ByteArray(1024)
            while (!deflater.finished()) {
                compressed.write(buffer, 0, deflater.deflate(buffer))
            }
        } finally {
            deflater.end()
        }
        fun chunk(type: String, data: ByteArray): ByteArray {
            val out = ByteArrayOutputStream()
            out.write(data.size ushr 24)
            out.write(data.size ushr 16)
            out.write(data.size ushr 8)
            out.write(data.size)
            val typeBytes = type.toByteArray(Charsets.US_ASCII)
            out.write(typeBytes)
            out.write(data)
            val crc = CRC32()
            crc.update(typeBytes)
            crc.update(data)
            val value = crc.value
            out.write((value ushr 24).toInt())
            out.write((value ushr 16).toInt())
            out.write((value ushr 8).toInt())
            out.write(value.toInt())
            return out.toByteArray()
        }
        val ihdr = ByteArrayOutputStream().apply {
            write(width ushr 24); write(width ushr 16); write(width ushr 8); write(width)
            write(height ushr 24); write(height ushr 16); write(height ushr 8); write(height)
            write(8) // bit depth
            write(6) // color type RGBA
            write(0); write(0); write(0)
        }.toByteArray()
        val png = ByteArrayOutputStream()
        png.write(byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A))
        png.write(chunk("IHDR", ihdr))
        png.write(chunk("IDAT", compressed.toByteArray()))
        png.write(chunk("IEND", ByteArray(0)))
        return png.toByteArray()
    }

    /**
     * pdfbox-android decodes images through android.graphics.Bitmap, which is
     * only available on a device/emulator. Skip image-embedding assertions in
     * plain JVM runs instead of reporting a false failure.
     */
    private fun requireAndroidGraphics() {
        val available = try {
            val bitmap = android.graphics.BitmapFactory.decodeByteArray(signature(), 0, signature().size)
            bitmap != null
        } catch (_: Throwable) {
            false
        }
        assumeTrue("Image embedding requires Android graphics (device/emulator).", available)
    }

    @Test fun signingPreservesOtherPagesAndPageGeometry() {
        requireAndroidGraphics()
        val input = source(pages = 2)
        val original = input.copyOf()
        val output = PdfSigner.apply(
            input, signature(), 0, "bottomRight", 0.3f, 0.12f, 0.04f, 0.04f, 1f,
        )
        assertArrayEquals(original, input)
        PDDocument.load(output).use { document ->
            assertEquals(2, document.numberOfPages)
            // Page 1 keeps its original media box; signing must not resize it.
            assertEquals(300f, document.getPage(0).mediaBox.width, 0.01f)
            assertEquals(400f, document.getPage(0).mediaBox.height, 0.01f)
            // Page 2 is untouched, so its dimensions and content remain.
            assertEquals(301f, document.getPage(1).mediaBox.width, 0.01f)
            assertTrue(document.getPage(0).contents.readBytes().isNotEmpty())
            assertTrue(document.getPage(1).contents.readBytes().isNotEmpty())
        }
    }

    @Test fun signsOnlyTheRequestedPage() {
        requireAndroidGraphics()
        val output = PdfSigner.apply(
            source(pages = 3), signature(), 2, "center", 0.3f, 0.12f, 0.04f, 0.04f, 1f,
        )
        PDDocument.load(output).use { document ->
            assertEquals(3, document.numberOfPages)
        }
    }

    @Test fun invalidInputsFailWithoutChangingBytes() {
        val input = source()
        val original = input.copyOf()
        // Empty signature is rejected before any image decoding is attempted.
        assertThrows(IllegalArgumentException::class.java) {
            PdfSigner.apply(input, ByteArray(0), 0, "center", 0.3f, 0.1f, 0f, 0f, 1f)
        }
        // Page bounds, size and opacity are validated before decoding too.
        assertThrows(IllegalArgumentException::class.java) {
            PdfSigner.apply(input, byteArrayOf(1), 5, "center", 0.3f, 0.1f, 0f, 0f, 1f)
        }
        assertThrows(IllegalArgumentException::class.java) {
            PdfSigner.apply(input, byteArrayOf(1), -1, "center", 0.3f, 0.1f, 0f, 0f, 1f)
        }
        assertThrows(IllegalArgumentException::class.java) {
            PdfSigner.apply(input, byteArrayOf(1), 0, "center", 0f, 0.1f, 0f, 0f, 1f)
        }
        assertThrows(IllegalArgumentException::class.java) {
            PdfSigner.apply(input, byteArrayOf(1), 0, "center", 0.3f, 0.1f, 0f, 0f, 0f)
        }
        assertArrayEquals(original, input)
    }

    @Test fun invalidPdfIsRejected() {
        assertThrows(Exception::class.java) {
            PdfSigner.apply("not a PDF".toByteArray(), byteArrayOf(1), 0, "center", 0.3f, 0.1f, 0f, 0f, 1f)
        }
    }
}
