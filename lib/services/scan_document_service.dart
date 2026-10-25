import 'dart:typed_data';

/// One captured document page.
///
/// A page owns the encoded image bytes that will be embedded into the PDF.
/// The bytes are kept in memory (and mirrored into the app's private cache
/// directory) so a page can be previewed, reordered, and re-cropped without
/// touching the user's files. The source file the camera wrote is deleted as
/// soon as its bytes have been read.
class ScanPage {
  const ScanPage({required this.bytes, required this.width, required this.height});

  /// Encoded JPEG bytes of the page.
  final Uint8List bytes;

  /// Pixel width of the page image.
  final int width;

  /// Pixel height of the page image.
  final int height;

  /// Approximate memory cost of the page, used to keep the status message
  /// honest about how much is held in RAM.
  int get byteLength => bytes.length;

  /// Returns a copy of this page with new image data.
  ScanPage withImage({
    required Uint8List bytes,
    required int width,
    required int height,
  }) => ScanPage(bytes: bytes, width: width, height: height);
}

/// Ordered, mutable list of captured pages.
///
/// Kept UI-free so the ordering and removal rules can be unit tested without
/// a camera. It mirrors the pattern used by the Image to PDF tool's
/// `ImageSelection`.
class ScanPageList {
  final List<ScanPage> _pages = [];

  List<ScanPage> get pages => List.unmodifiable(_pages);
  int get length => _pages.length;
  bool get isEmpty => _pages.isEmpty;
  bool get isNotEmpty => _pages.isNotEmpty;

  /// Appends a page to the end of the document.
  void add(ScanPage page) => _pages.add(page);

  /// Removes the page at [index].
  void removeAt(int index) {
    RangeError.checkValidIndex(index, _pages);
    _pages.removeAt(index);
  }

  /// Moves the page at [from] to [to], keeping the rest of the order intact.
  void move(int from, int to) {
    RangeError.checkValidIndex(from, _pages);
    RangeError.checkValidIndex(to, _pages);
    _pages.insert(to, _pages.removeAt(from));
  }

  /// Replaces the page at [index] with [page].
  void replaceAt(int index, ScanPage page) {
    RangeError.checkValidIndex(index, _pages);
    _pages[index] = page;
  }

  /// Removes every page.
  void clear() => _pages.clear();
}
