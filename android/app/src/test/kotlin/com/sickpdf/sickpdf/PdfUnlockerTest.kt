package com.sickpdf.sickpdf

import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.encryption.AccessPermission
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import com.tom_roush.pdfbox.pdmodel.encryption.StandardProtectionPolicy
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream

class PdfUnlockerTest {
    private fun encrypted(): ByteArray = PDDocument().use { document ->
        document.addPage(PDPage())
        PDPageContentStream(document, document.getPage(0)).use { it.addRect(10f, 10f, 20f, 20f); it.fill() }
        val policy = StandardProtectionPolicy("owner", "secret", AccessPermission())
        policy.encryptionKeyLength = 128
        document.protect(policy)
        ByteArrayOutputStream().use { document.save(it); it.toByteArray() }
    }

    @Test fun correctPasswordProducesPlainPdfAndWrongPasswordFails() {
        val input = encrypted()
        val original = input.copyOf()
        val output = PdfUnlocker.unlock(input, "secret")
        assertArrayEquals(original, input)
        PDDocument.load(output).use { assertFalse(it.isEncrypted); assertEquals(1, it.numberOfPages) }
        assertThrows(InvalidPasswordException::class.java) { PdfUnlocker.unlock(input, "wrong") }
    }

    @Test fun emptyPasswordAndInvalidPdfFail() {
        assertThrows(IllegalArgumentException::class.java) { PdfUnlocker.unlock(encrypted(), "") }
        assertThrows(Exception::class.java) { PdfUnlocker.unlock("not pdf".toByteArray(), "secret") }
    }
}
