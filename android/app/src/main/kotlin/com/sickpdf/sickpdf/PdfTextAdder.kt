package com.sickpdf.sickpdf

import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.min

/**
 * Adds a text overlay to selected pages by appending a content stream to each
 * page. APPEND mode preserves the original page content, vector data, images,
 * page dimensions and orientation: nothing is rasterized.
 *
 * The text is placed inside a vertical band (top/center/bottom) and clamped to
 * the page edges so it never clips outside the media box.
 */
internal object PdfTextAdder {
    private const val MARGIN = 24f

    fun apply(
        input: ByteArray,
        text: String,
        fontSize: Float,
        colorR: Float,
        colorG: Float,
        colorB: Float,
        alignment: String,
        vertical: String,
        pages: List<Int>?,
    ): ByteArray {
        require(text.isNotBlank()) { "Enter the text to add." }
        require(fontSize in 6f..144f) { "Font size must be between 6 and 144." }
        require(colorR in 0f..1f && colorG in 0f..1f && colorB in 0f..1f) {
            "Invalid text color."
        }
        PDDocument.load(ByteArrayInputStream(input)).use { document ->
            val pageCount = document.numberOfPages
            require(pageCount > 0) { "This PDF has no valid pages." }
            val selected = pages?.toSet()
                ?: document.pages.mapIndexed { index, _ -> index }.toSet()
            require(selected.isNotEmpty() && selected.all { it in 0 until pageCount }) {
                "Select at least one valid page."
            }
            val font = PDType1Font.HELVETICA
            document.pages.forEachIndexed { index, page ->
                if (index !in selected) return@forEachIndexed
                val box = page.mediaBox
                val width = box.width
                val height = box.height
                val textWidth = font.getStringWidth(text) / 1000f * fontSize
                val x = when {
                    alignment == "left" -> MARGIN
                    alignment == "right" -> max(MARGIN, width - textWidth - MARGIN)
                    else -> (width - textWidth) / 2f
                }
                // Keep the text within the page edges even for narrow pages.
                val clampedX = max(0f, min(x, max(0f, width - textWidth)))
                val y = when (vertical) {
                    "top" -> height - MARGIN - fontSize
                    "bottom" -> MARGIN
                    else -> (height - fontSize) / 2f
                }
                val clampedY = max(0f, min(y, max(0f, height - fontSize)))
                PDPageContentStream(
                    document,
                    page,
                    PDPageContentStream.AppendMode.APPEND,
                    true,
                    true,
                ).use { stream ->
                    stream.setNonStrokingColor(colorR, colorG, colorB)
                    stream.beginText()
                    stream.setFont(font, fontSize)
                    stream.newLineAtOffset(clampedX, clampedY)
                    stream.showText(text)
                    stream.endText()
                }
            }
            val output = ByteArrayOutputStream()
            document.save(output)
            return output.toByteArray().also { check(it.isNotEmpty()) }
        }
    }
}
