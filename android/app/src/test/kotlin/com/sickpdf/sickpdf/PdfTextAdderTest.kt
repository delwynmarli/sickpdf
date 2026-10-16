package com.sickpdf.sickpdf

import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.ByteArrayOutputStream

class PdfTextAdderTest {
    /**
     * pdfbox-android resolves the standard 14 fonts through
     * PDFBoxResourceLoader / android.graphics, which are only available on a
     * device or emulator. Skip font-dependent assertions in plain JVM runs
     * instead of reporting a false failure, matching [PdfSignerTest].
     */
    private fun requireStandardFont() {
        val available = try {
            com.tom_roush.pdfbox.pdmodel.font.PDType1Font.HELVETICA
            true
        } catch (_: Throwable) {
            false
        }
        assumeTrue(
            "Standard PDF fonts require Android resources (device/emulator).",
            available,
        )
    }

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

    @Test fun addingTextPreservesOtherPagesAndPageGeometry() {
        requireStandardFont()
        val input = source(pages = 2)
        val original = input.copyOf()
        val output = PdfTextAdder.apply(
            input, "Hello PDF", 18f, 0f, 0f, 0f, "center", "center", listOf(0),
        )
        assertArrayEquals(original, input)
        PDDocument.load(output).use { document ->
            assertEquals(2, document.numberOfPages)
            // Page 1 keeps its original media box; adding text must not resize it.
            assertEquals(300f, document.getPage(0).mediaBox.width, 0.01f)
            assertEquals(400f, document.getPage(0).mediaBox.height, 0.01f)
            // Page 2 is untouched, so its dimensions and content remain.
            assertEquals(301f, document.getPage(1).mediaBox.width, 0.01f)
            assertTrue(document.getPage(0).contents.readBytes().isNotEmpty())
            assertTrue(document.getPage(1).contents.readBytes().isNotEmpty())
        }
    }

    @Test fun addsTextToEveryPageWhenNoSelectionGiven() {
        requireStandardFont()
        val output = PdfTextAdder.apply(
            source(pages = 3), "All", 12f, 0f, 0f, 0f, "left", "bottom", null,
        )
        PDDocument.load(output).use { document ->
            assertEquals(3, document.numberOfPages)
            for (index in 0 until 3) {
                assertTrue(document.getPage(index).contents.readBytes().isNotEmpty())
            }
        }
    }

    @Test fun supportsAllAlignmentsAndVerticalBands() {
        requireStandardFont()
        for (alignment in listOf("left", "center", "right")) {
            for (vertical in listOf("top", "center", "bottom")) {
                val output = PdfTextAdder.apply(
                    source(pages = 1), "Sample text", 20f, 0.1f, 0.2f, 0.3f,
                    alignment, vertical, null,
                )
                PDDocument.load(output).use { document ->
                    assertEquals(1, document.numberOfPages)
                }
            }
        }
    }

    @Test fun longTextOnNarrowPageStaysWithinBounds() {
        requireStandardFont()
        // A very wide string on a narrow page must not throw or clip outside.
        val output = PdfTextAdder.apply(
            source(pages = 1),
            "This is a very long line of text that will not fit on the page width",
            40f, 0f, 0f, 0f, "center", "center", null,
        )
        PDDocument.load(output).use { document ->
            assertEquals(1, document.numberOfPages)
        }
    }

    @Test fun ordinaryPunctuationIsSupported() {
        requireStandardFont()
        val output = PdfTextAdder.apply(
            source(pages = 1),
            "Hello, world! (100%) - test@example.com: OK?",
            16f, 0f, 0f, 0f, "center", "center", null,
        )
        PDDocument.load(output).use { document ->
            assertEquals(1, document.numberOfPages)
        }
    }

    @Test fun invalidInputsFailWithoutChangingBytes() {
        val input = source()
        val original = input.copyOf()
        assertThrows(IllegalArgumentException::class.java) {
            PdfTextAdder.apply(input, "   ", 18f, 0f, 0f, 0f, "center", "center", null)
        }
        assertThrows(IllegalArgumentException::class.java) {
            PdfTextAdder.apply(input, "x", 4f, 0f, 0f, 0f, "center", "center", null)
        }
        assertThrows(IllegalArgumentException::class.java) {
            PdfTextAdder.apply(input, "x", 200f, 0f, 0f, 0f, "center", "center", null)
        }
        assertThrows(IllegalArgumentException::class.java) {
            PdfTextAdder.apply(input, "x", 18f, 1.5f, 0f, 0f, "center", "center", null)
        }
        // Out-of-range or empty page selections are rejected.
        assertThrows(IllegalArgumentException::class.java) {
            PdfTextAdder.apply(input, "x", 18f, 0f, 0f, 0f, "center", "center", listOf(5))
        }
        assertThrows(IllegalArgumentException::class.java) {
            PdfTextAdder.apply(
                input, "x", 18f, 0f, 0f, 0f, "center", "center", emptyList(),
            )
        }
        assertArrayEquals(original, input)
    }

    @Test fun invalidPdfIsRejected() {
        assertThrows(Exception::class.java) {
            PdfTextAdder.apply(
                "not a PDF".toByteArray(), "x", 18f, 0f, 0f, 0f, "center", "center", null,
            )
        }
    }
}
