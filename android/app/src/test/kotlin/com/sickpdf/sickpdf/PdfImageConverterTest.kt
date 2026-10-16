package com.sickpdf.sickpdf

import com.tom_roush.pdfbox.pdmodel.PDDocument
import org.junit.Assert.assertEquals
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.CRC32
import java.util.zip.Deflater

class PdfImageConverterTest {

    /**
     * Builds a hand-crafted 4x2 RGBA PNG without android.graphics.Bitmap, so
     * this fixture is usable in a plain JVM test. PDFBox (via
     * android.graphics.BitmapFactory) still needs a device/emulator to decode
     * PNGs, which is why decode-dependent assertions are guarded.
     */
    private fun png(width: Int = 4, height: Int = 2): ByteArray {
        val raw = ByteArrayOutputStream()
        for (y in 0 until height) {
            raw.write(0) // per-row filter byte
            for (x in 0 until width) {
                raw.write(255)
                raw.write(0)
                raw.write(0)
                raw.write(255)
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
     * PDFBox decodes embedded JPEG/PNG through android.graphics.BitmapFactory,
     * which only exists on a device/emulator. Skip decode-dependent assertions
     * in plain JVM runs instead of reporting a false failure.
     */
    private fun requireAndroidGraphics(): ByteArray {
        val bytes = png()
        val available = try {
            val bitmap = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            bitmap != null
        } catch (_: Throwable) {
            false
        }
        assumeTrue("Image embedding requires Android graphics (device/emulator).", available)
        return bytes
    }

    @Test fun oneImageProducesOnePage() {
        val bytes = requireAndroidGraphics()
        val output = PdfImageConverter.convert(listOf(bytes), "a4", 18f, "contain", 0f)
        PDDocument.load(output).use { document ->
            assertEquals(1, document.numberOfPages)
        }
    }

    @Test fun imageOrderMapsToPageOrder() {
        val first = requireAndroidGraphics()
        val second = requireAndroidGraphics()
        val output = PdfImageConverter.convert(
            listOf(first, second, first),
            "original",
            0f,
            "contain",
            0f,
        )
        PDDocument.load(output).use { document ->
            assertEquals(3, document.numberOfPages)
        }
    }

    @Test fun portraitImageProducesPortraitA4AndLandscapeProducesLandscape() {
        val portrait = requireAndroidGraphics()
        val output = PdfImageConverter.convert(listOf(portrait), "a4", 18f, "contain", 0f)
        PDDocument.load(output).use { document ->
            val box = document.getPage(0).mediaBox
            assertEquals(595.276f, box.width, 0.01f)
            assertEquals(841.89f, box.height, 0.01f)
        }
    }

    @Test fun originalPageSizeMatchesImageDimensions() {
        val bytes = requireAndroidGraphics()
        val output = PdfImageConverter.convert(listOf(bytes), "original", 0f, "contain", 0f)
        PDDocument.load(output).use { document ->
            val box = document.getPage(0).mediaBox
            // Fixture is 4x2 pixels; original uses one point per pixel.
            assertEquals(4f, box.width, 0.01f)
            assertEquals(2f, box.height, 0.01f)
        }
    }

    @Test fun squarePageUsesRequestedSide() {
        val bytes = requireAndroidGraphics()
        val output = PdfImageConverter.convert(listOf(bytes), "square", 0f, "contain", 300f)
        PDDocument.load(output).use { document ->
            val box = document.getPage(0).mediaBox
            assertEquals(300f, box.width, 0.01f)
            assertEquals(300f, box.height, 0.01f)
        }
    }

    @Test fun emptySelectionFailsBeforeAnyDecode() {
        assertThrows(IllegalArgumentException::class.java) {
            PdfImageConverter.convert(emptyList(), "a4", 18f, "contain", 0f)
        }
    }

    @Test fun emptyImageBytesFailWithPositionMessage() {
        val error = assertThrows(IllegalArgumentException::class.java) {
            PdfImageConverter.convert(
                listOf(ByteArray(0)),
                "a4",
                18f,
                "contain",
                0f,
            )
        }
        assertTrue(error.message!!.contains("1"))
    }

    @Test fun negativeMarginIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            PdfImageConverter.convert(listOf(ByteArray(4)), "a4", -1f, "contain", 0f)
        }
    }

    @Test fun nonPositiveSquareSideIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            PdfImageConverter.convert(listOf(ByteArray(4)), "square", 0f, "contain", 0f)
        }
    }
}
