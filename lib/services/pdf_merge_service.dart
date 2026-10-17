import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_combiner/exception/pdf_combiner_exception.dart';
import 'package:pdf_combiner/models/merge_input.dart';
import 'package:pdf_combiner/pdf_combiner.dart';

class PdfMergeService {
  /// Merges [inputPaths] and returns the output bytes.
  ///
  /// A private temporary output file is created and always deleted, so callers
  /// never manage temp paths and the user's original files are never touched.
  /// [outputPath] may be supplied by tests to control the destination.
  Future<Uint8List> merge({
    required List<String> inputPaths,
    String? outputPath,
  }) async {
    if (inputPaths.length < 2) {
      throw const FormatException('Select at least two PDF files to merge.');
    }

    final temporaryFile = File(
      outputPath ??
          '${Directory.systemTemp.path}${Platform.pathSeparator}sickpdf_merge_${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    developer.log(
      'Merging ${inputPaths.length} local PDF files.',
      name: 'sickpdf.merge',
    );
    try {
      for (var index = 0; index < inputPaths.length; index++) {
        final input = File(inputPaths[index]);
        if (input.absolute.path == temporaryFile.absolute.path) {
          throw const FormatException(
            'Output must not overwrite an input PDF.',
          );
        }
        if (!await input.exists() || await input.length() == 0) {
          throw FormatException(
            'PDF ${index + 1} is missing or empty. Remove it and select it again.',
          );
        }
      }
      await PdfCombiner.mergeMultiplePDFs(
        inputs: inputPaths.map(MergeInput.path).toList(),
        outputPath: temporaryFile.path,
      );
      if (!await temporaryFile.exists()) {
        throw const FileSystemException('The PDF was not created.');
      }
      final bytes = await temporaryFile.readAsBytes();
      if (bytes.isEmpty) {
        throw const FileSystemException('The generated PDF is empty.');
      }
      return bytes;
    } on PdfCombinerException {
      throw const FormatException(
        'Could not merge these PDFs. A file may be damaged, password-protected, or unsupported. Try unlocked PDFs or remove the affected file.',
      );
    } finally {
      try {
        if (!inputPaths.any(
              (path) => File(path).absolute.path == temporaryFile.absolute.path,
            ) &&
            await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      } on FileSystemException {
        developer.log(
          'Temporary PDF cleanup failed; the operating system may clear it later.',
          name: 'sickpdf.merge',
        );
      }
    }
  }
}
