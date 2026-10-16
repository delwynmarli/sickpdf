package com.sickpdf.sickpdf

import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlin.math.max

/**
 * Adds page numbers as a text overlay by appending a content stream to each
 * selected page. APPEND mode preserves the original page content, vector data,
 * images, page dimensions and orientation: nothing is rasterized.
 */
internal object PdfPageNumberer {
    private const val MARGIN = 24f

    fun apply(
        input: ByteArray,
        format: String,
        position: String,
        startNumber: Int,
        firstPage: Int,
        lastPage: Int,
        fontSize: Float,
        colorR: Float,
        colorG: Float,
        colorB: Float,
    ): ByteArray {
        require(fontSize in 6f..72f) { "Font size must be between 6 and 72." }
        require(colorR in 0f..1f && colorG in 0f..1f && colorB in 0f..1f) { "Invalid text color." }
        PDDocument.load(ByteArrayInputStream(input)).use { document ->
            val pageCount = document.numberOfPages
            require(pageCount > 0) { "This PDF has no valid pages." }
            // firstPage/lastPage are 1-based page numbers.
            require(firstPage in 1..pageCount) { "First page must be within 1 and $pageCount." }
            require(lastPage in 1..pageCount) { "Last page must be within 1 and $pageCount." }
            require(firstPage <= lastPage) { "First page must not exceed the last page." }
            val font = PDType1Font.HELVETICA
            for (index in (firstPage - 1)..(lastPage - 1)) {
                val page = document.getPage(index)
                val box = page.mediaBox
                val width = box.width
                val height = box.height
                val number = startNumber + (index - (firstPage - 1))
                val label = when (format) {
                    "page" -> "Page $number"
                    "pageOfN" -> "Page $number of ${startNumber + (lastPage - firstPage)}"
                    else -> number.toString()
                }
                val textWidth = font.getStringWidth(label) / 1000f * fontSize
                val x = when {
                    position.endsWith("left") -> MARGIN
                    position.endsWith("right") -> max(MARGIN, width - textWidth - MARGIN)
                    else -> max(MARGIN, (width - textWidth) / 2f)
                }
                val y = if (position.startsWith("top")) {
                    height - MARGIN - fontSize
                } else {
                    MARGIN
                }
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
                    stream.newLineAtOffset(x, y)
                    stream.showText(label)
                    stream.endText()
                }
            }
            val output = ByteArrayOutputStream()
            document.save(output)
            return output.toByteArray().also { check(it.isNotEmpty()) }
        }
    }
}
