package com.sickpdf.sickpdf

import com.tom_roush.pdfbox.cos.COSDictionary
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.encryption.AccessPermission
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import com.tom_roush.pdfbox.pdmodel.encryption.StandardProtectionPolicy
import java.io.ByteArrayOutputStream
import java.security.SecureRandom

/** No filesystem writes, logging, or persistent password storage. */
internal object PdfProtector {
    fun protect(input: ByteArray, password: String): ByteArray {
        require(password.isNotBlank() && password.length <= 127 &&
            password.all { it.code in 32..126 }) { "Invalid password." }
        PDDocument.load(input).use { document ->
            require(document.numberOfPages > 0) { "No pages." }
            // Do not silently replace existing document security or permissions.
            require(!document.isEncrypted) { "Already encrypted." }
            require(document.signatureDictionaries.isEmpty()) { "Signed PDF." }
            val ownerBytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val owner = ownerBytes.joinToString("") { "%02x".format(it) }
            ownerBytes.fill(0)
            val policy = StandardProtectionPolicy(owner, password, AccessPermission())
            policy.encryptionKeyLength = 256
            policy.isPreferAES = true
            document.protect(policy)
            // PDFBox does not upgrade the source version for revision 6 itself.
            if (document.version < 2.0f) {
                document.version = 1.7f
                document.documentCatalog.version = "1.7"
                val catalog = document.documentCatalog.cosObject
                val extensions = (catalog.getDictionaryObject(COSName.getPDFName("Extensions"))
                    as? COSDictionary) ?: COSDictionary().also {
                    catalog.setItem(COSName.getPDFName("Extensions"), it)
                }
                val adobeName = COSName.getPDFName("ADBE")
                val adobe = (extensions.getDictionaryObject(adobeName) as? COSDictionary)
                    ?: COSDictionary().also { extensions.setItem(adobeName, it) }
                adobe.setName(COSName.getPDFName("BaseVersion"), "1.7")
                adobe.setInt(COSName.getPDFName("ExtensionLevel"),
                    maxOf(8, adobe.getInt(COSName.getPDFName("ExtensionLevel"), 0)))
            }
            val output = ByteArrayOutputStream().use {
                document.save(it)
                it.toByteArray()
            }
            check(output.isNotEmpty())
            // Fail closed: never hand unprotected output to the export flow.
            PDDocument.load(output, password).use {
                check(it.isEncrypted && it.numberOfPages == document.numberOfPages)
                check(it.encryption.length == 256 && it.encryption.revision == 6)
            }
            checkRejected(output, "")
            checkRejected(output, "sickPDF-invalid-$owner")
            return output
        }
    }

    private fun checkRejected(bytes: ByteArray, password: String) {
        try {
            PDDocument.load(bytes, password).use { }
        } catch (_: InvalidPasswordException) {
            return
        }
        error("Encryption verification failed.")
    }
}
