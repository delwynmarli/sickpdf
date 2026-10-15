import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

/// Additional clockwise quarter turns, independent of each source orientation.
class PdfPageRotations {
  PdfPageRotations(int count) : _turns = List.filled(count, 0);
  final List<int> _turns;
  List<int> get turns => List.unmodifiable(_turns);

  void rotate(Iterable<int> pages, int delta) {
    final indices = pages.toSet();
    for (final index in indices) {
      RangeError.checkValidIndex(index, _turns);
    }
    for (final index in indices) {
      _turns[index] = (_turns[index] + delta) % 4;
    }
  }
}

/// Reopens a private snapshot to preserve document structures and avoid mutating
/// the thumbnail session. Only page /Rotate values are edited; no rasterization.
Future<Uint8List> generateRotatedPdf(
  PdfDocument source,
  List<int> turns,
) async {
  final snapshot = List<int>.of(turns);
  if (snapshot.length != source.pages.length ||
      snapshot.isEmpty ||
      snapshot.any((turn) => turn < 0 || turn > 3)) {
    throw const FormatException(
      'Invalid page rotations. Select the PDF again.',
    );
  }
  final copy = await PdfDocument.openData(await source.encodePdf());
  try {
    copy.pages = [
      for (var i = 0; i < snapshot.length; i++)
        copy.pages[i].rotatedBy(PdfPageRotation.values[snapshot[i]]),
    ];
    final bytes = await copy.encodePdf();
    if (bytes.isEmpty) {
      throw const FormatException('The generated PDF is empty.');
    }
    return bytes;
  } finally {
    await copy.dispose();
  }
}
