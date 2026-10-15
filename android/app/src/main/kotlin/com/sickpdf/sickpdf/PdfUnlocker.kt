package com.sickpdf.sickpdf

import com.tom_roush.pdfbox.pdmodel.PDDocument
import java.io.ByteArrayOutputStream

/** Opens an encrypted PDF with the supplied password and writes a new plain PDF. */
internal object PdfUnlocker {
    fun unlock(input: ByteArray, password: String): ByteArray {
        require(password.isNotEmpty()) { "Password required." }
        PDDocument.load(input, password).use { document ->
            require(document.numberOfPages > 0) { "No pages." }
            require(document.signatureDictionaries.isEmpty()) { "Signed PDF." }
            // A successful load decrypts the document in memory, but PDFBox keeps
            // the source security dictionary unless explicitly removed before save.
            document.setAllSecurityToBeRemoved(true)
            val output = ByteArrayOutputStream().use {
                document.save(it)
                it.toByteArray()
            }
            check(output.isNotEmpty())
            PDDocument.load(output).use { verified ->
                check(!verified.isEncrypted && verified.numberOfPages == document.numberOfPages)
            }
            return output
        }
    }
}
