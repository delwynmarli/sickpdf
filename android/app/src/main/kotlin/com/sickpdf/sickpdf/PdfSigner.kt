package com.sickpdf.sickpdf

import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.graphics.image.PDImageXObject
import com.tom_roush.pdfbox.pdmodel.graphics.state.PDExtendedGraphicsState
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlin.math.max

/**
 * Draws a signature image onto a single page by appending a content stream.
 *
 * Only the signature image XObject is added. The original page content is left
 * untouched and is NOT rasterized: vector art, embedded images, page
 * dimensions, orientation and quality are preserved. The PNG's alpha channel
 * provides the transparent background.
 *
 * Position and size are expressed as fractions of the page media box so the
 * result scales consistently across page sizes.
 */
internal object PdfSigner {
    fun apply(
        input: ByteArray,
        signature: ByteArray,
        pageIndex: Int,
        position: String,
        widthFraction: Float,
        heightFraction: Float,
        offsetXFraction: Float,
        offsetYFraction: Float,
        opacity: Float,
    ): ByteArray {
        require(signature.isNotEmpty()) { "Draw or upload a signature first." }
        require(widthFraction > 0f && widthFraction <= 1f) {
            "Signature width must be between 1% and 100%."
        }
        require(heightFraction > 0f && heightFraction <= 1f) {
            "Signature height must be between 1% and 100%."
        }
        require(offsetXFraction in 0f..1f && offsetYFraction in 0f..1f) {
            "Signature margins must be between 0% and 100%."
        }
        require(opacity > 0f && opacity <= 1f) { "Opacity must be between 1% and 100%." }

        PDDocument.load(ByteArrayInputStream(input)).use { document ->
            val pageCount = document.numberOfPages
            require(pageCount > 0) { "This PDF has no valid pages." }
            require(pageIndex in 0 until pageCount) {
                "Choose a page between 1 and $pageCount."
            }

            val page = document.getPage(pageIndex)
            val box = page.mediaBox
            val pageWidth = box.width
            val pageHeight = box.height

            // Decode the transparent PNG into a lossless image XObject.
            val image = PDImageXObject.createFromByteArray(document, signature, "signature")

            // Aspect ratio of the drawn signature keeps strokes undistorted.
            val width = pageWidth * widthFraction
            val height = pageHeight * heightFraction
            val marginX = pageWidth * offsetXFraction
            val marginY = pageHeight * offsetYFraction

            val x = when {
                position.endsWith("Right") -> max(marginX, pageWidth - width - marginX)
                position.endsWith("Left") -> marginX
                else -> max(0f, (pageWidth - width) / 2f)
            }
            val y = when {
                position.startsWith("Top") -> max(marginY, pageHeight - height - marginY)
                position.startsWith("Bottom") -> marginY
                else -> max(0f, (pageHeight - height) / 2f)
            }

            PDPageContentStream(
                document,
                page,
                PDPageContentStream.AppendMode.APPEND,
                true,
                true,
            ).use { stream ->
                if (opacity < 1f) {
                    val state = PDExtendedGraphicsState().apply {
                        nonStrokingAlphaConstant = opacity
                    }
                    stream.setGraphicsStateParameters(state)
                }
                stream.drawImage(image, x, y, width, height)
            }

            val output = ByteArrayOutputStream()
            document.save(output)
            return output.toByteArray().also { check(it.isNotEmpty()) }
        }
    }
}
