package com.sickpdf.sickpdf

import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import com.tom_roush.pdfbox.pdmodel.interactive.digitalsignature.PDSignature
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File

class PdfProtectorTest {
    private fun source(): ByteArray = PDDocument().use { document ->
        repeat(2) {
            val page = PDPage()
            document.addPage(page)
            PDPageContentStream(document, page).use { stream ->
                stream.addRect(20f, 30f, 80f, 100f)
                stream.fill()
            }
        }
        ByteArrayOutputStream().use { output ->
            document.save(output)
            output.toByteArray()
        }
    }

    @Test fun realAes256EncryptionAndSourceUnchanged() {
        val input = source()
        val original = input.copyOf()
        val proof = File("../../build/protect-proof").apply { mkdirs() }
        val sourceFile = File(proof, "source.pdf").apply { writeBytes(input) }
        val output = PdfProtector.protect(input, "Test-only strong password 42!")
        assertArrayEquals(original, input)
        assertArrayEquals(original, sourceFile.readBytes())
        PDDocument.load(output, "Test-only strong password 42!").use {
            assertEquals(2, it.numberOfPages)
            assertTrue(it.isEncrypted)
            assertEquals(256, it.encryption.length)
            assertEquals(6, it.encryption.revision)
            assertEquals(1.7f, it.version)
            val extensions = it.documentCatalog.cosObject
                .getCOSDictionary(COSName.getPDFName("Extensions"))
            assertEquals(8, extensions.getCOSDictionary(COSName.getPDFName("ADBE"))
                .getInt(COSName.getPDFName("ExtensionLevel")))
            assertEquals("AESV3", it.encryption.stdCryptFilterDictionary.cosObject.getNameAsString("CFM"))
            assertTrue(it.getPage(0).contents.readBytes().isNotEmpty())
        }
        for (password in listOf("", "wrong")) {
            assertThrows(InvalidPasswordException::class.java) {
                PDDocument.load(output, password).close()
            }
        }
        // Synthetic artifacts for independent PDFium verification on the host.
        File(proof, "protected.pdf").writeBytes(output)
    }

    @Test fun invalidInputsFailWithoutChangingBytes() {
        for (password in listOf("", "   ", "x".repeat(128), "non-ascii-\u00e9")) {
            assertThrows(IllegalArgumentException::class.java) {
                PdfProtector.protect(source(), password)
            }
        }
        assertThrows(Exception::class.java) {
            PdfProtector.protect("not a PDF".toByteArray(), "secret")
        }
        val emptyPdf = PDDocument().use { document ->
            ByteArrayOutputStream().use { output ->
                document.save(output)
                output.toByteArray()
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            PdfProtector.protect(emptyPdf, "secret")
        }
    }

    @Test fun existingEncryptionAndSignaturesAreRejected() {
        val encrypted = PdfProtector.protect(source(), "secret")
        assertThrows(InvalidPasswordException::class.java) {
            PdfProtector.protect(encrypted, "new password")
        }
        val signed = PDDocument.load(source()).use { document ->
            document.addSignature(PDSignature())
            ByteArrayOutputStream().use { output ->
                document.save(output)
                output.toByteArray()
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            PdfProtector.protect(signed, "secret")
        }
    }

    @Test fun maximumLengthPasswordIsNotTruncated() {
        val password = "z".repeat(127)
        val output = PdfProtector.protect(source(), password)
        PDDocument.load(output, password).use { assertEquals(2, it.numberOfPages) }
        assertThrows(InvalidPasswordException::class.java) {
            PDDocument.load(output, "!" + password.substring(1)).close()
        }
    }
}
