# Security Policy

## Reporting a vulnerability

sickPDF processes documents entirely on-device, which limits the attack surface — but issues are still possible (for example, crashes or memory-safety problems in native PDF engines, or unintended file access).

If you believe you have found a security vulnerability, please open a [GitHub issue](https://github.com/delwynmarli/sickpdf/issues) marked as a security concern, or contact the repository owner through GitHub. Include:

- A description of the issue and its potential impact
- Steps or a proof of concept to reproduce it
- The affected version/commit

Please do not include confidential documents or exploit code in public issues. For reports that should not be public, contact the owner privately via GitHub before filing.

There is no paid response-time commitment for this project; reports are reviewed on a best-effort basis and acknowledged once triaged.

## Scope notes

- The app makes no network calls during document processing. Reports about third-party cloud providers accessible through the system document picker are out of scope.
- The release build currently uses debug signing; this is a known pre-release limitation, not a vulnerability.
- Vulnerabilities in the bundled PDF engines (`pdfrx`/PDFium, `pdf_combiner`) may need to be reported upstream as well.
