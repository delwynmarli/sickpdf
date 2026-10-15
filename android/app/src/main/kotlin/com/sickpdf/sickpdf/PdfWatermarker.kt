package com.sickpdf.sickpdf

import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.font.PDType1Font
import com.tom_roush.pdfbox.pdmodel.graphics.state.PDExtendedGraphicsState
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlin.math.max

internal object PdfWatermarker {
    fun apply(input: ByteArray, text: String, fontSize: Float, opacity: Float,
              position: String, rotation: String, pages: List<Int>?): ByteArray {
        require(text.isNotBlank()) { "Enter watermark text." }
        require(fontSize in 8f..144f) { "Text size must be between 8 and 144." }
        require(opacity > 0f && opacity <= 1f) { "Opacity must be between 1% and 100%." }
        PDDocument.load(ByteArrayInputStream(input)).use { document ->
            require(document.numberOfPages > 0) { "This PDF has no valid pages." }
            val selected = pages?.toSet() ?: document.pages.mapIndexed { index, _ -> index }.toSet()
            require(selected.isNotEmpty() && selected.all { it in 0 until document.numberOfPages }) {
                "Select at least one valid page."
            }
            document.pages.forEachIndexed { index, page ->
                if (index !in selected) return@forEachIndexed
                val box = page.mediaBox
                val width = box.width
                val height = box.height
                val font = PDType1Font.HELVETICA_BOLD
                val textWidth = font.getStringWidth(text) / 1000f * fontSize
                val x = max(8f, (width - textWidth) / 2f)
                val y = when (position) {
                    "top" -> height - fontSize * 2f
                    "bottom" -> fontSize * 1.5f
                    else -> (height - fontSize) / 2f
                }
                val angle = if (rotation == "diagonal") Math.toRadians(45.0) else 0.0
                PDPageContentStream(document, page, PDPageContentStream.AppendMode.APPEND, true, true).use { stream ->
                    val state = PDExtendedGraphicsState().apply { nonStrokingAlphaConstant = opacity }
                    stream.setGraphicsStateParameters(state)
                    stream.setNonStrokingColor(90, 90, 90)
                    stream.beginText()
                    stream.setFont(font, fontSize)
                    stream.setTextMatrix(
                        Math.cos(angle), Math.sin(angle),
                        -Math.sin(angle), Math.cos(angle), x.toDouble(), y.toDouble(),
                    )
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
