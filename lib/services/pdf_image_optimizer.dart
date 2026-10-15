import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as native;

/// Uses the SAME loaded PDFium instance under pdfrx's exclusive native lock.
/// The worker owns all temporary native handles; no PDFium calls overlap.
Future<Map<String, int>> optimizePdfImages(
  PdfDocument document,
  int dpi,
  int quality,
) {
  final module = Pdfrx.pdfiumModulePath;
  return document.useNativeDocumentHandle(
    (address) => Isolate.run(() => _optimize(address, module, dpi, quality)),
  );
}

Map<String, int> _optimize(int address, String? module, int dpi, int quality) {
  final pdf = native.getPdfium(modulePath: module);
  final doc = Pointer<native.fpdf_document_t__>.fromAddress(address);
  var changed = 0;
  final stats = <String, int>{};
  void count(String reason) =>
      stats.update(reason, (n) => n + 1, ifAbsent: () => 1);
  for (var p = 0; p < pdf.FPDF_GetPageCount(doc); p++) {
    final page = pdf.FPDF_LoadPage(doc, p);
    if (page == nullptr) {
      throw StateError('Could not load page for image optimization.');
    }
    try {
      var dirty = false;
      final images = <(native.FPDF_PAGEOBJECT, double, double)>[];
      void inspect(native.FPDF_PAGEOBJECT object) {
        final type = pdf.FPDFPageObj_GetType(object);
        if (type == 5) {
          // PDFium page regeneration does not persist nested image replacements.
          count('Form XObject unsupported');
          return;
        }
        if (type != 3) return;
        using((arena) {
          final matrix = arena<native.FS_MATRIX>();
          if (pdf.FPDFPageObj_GetMatrix(object, matrix) == 0) {
            count('missing transform');
            return;
          }
          final t = matrix.ref;
          if (pdf.FPDFPageObj_HasTransparency(object) != 0) {
            count('transparency');
            return;
          }
          images.add((
            object,
            math.sqrt(t.a * t.a + t.b * t.b),
            math.sqrt(t.c * t.c + t.d * t.d),
          ));
        });
      }

      for (var i = 0; i < pdf.FPDFPage_CountObjects(page); i++) {
        inspect(pdf.FPDFPage_GetObject(page, i));
      }
      for (final entry in images) {
        final (object, displayWidth, displayHeight) = entry;
        count('images inspected');
        final replaced = using((arena) {
          final metadata = arena<native.FPDF_IMAGEOBJ_METADATA>();
          if (pdf.FPDFImageObj_GetImageMetadata(object, page, metadata) == 0) {
            return false;
          }
          final m = metadata.ref;
          // Opaque DeviceGray and DeviceRGB only; never convert masks/CMYK/ICC.
          if (!((m.colorspace == 2 && m.bits_per_pixel == 24) ||
                  (m.colorspace == 1 && m.bits_per_pixel == 8)) ||
              m.marked_content_id >= 0 ||
              m.width < 64 ||
              m.height < 64 ||
              m.width * m.height > 16000000) {
            count('unsupported color, tagged or size-limited');
            return false;
          }
          if (!displayWidth.isFinite || !displayHeight.isFinite) return false;
          final scale = math.min(
            1.0,
            math.max(
              displayWidth * dpi / 72 / m.width,
              displayHeight * dpi / 72 / m.height,
            ),
          );
          if (scale <= 0) return false;
          final bitmap = pdf.FPDFImageObj_GetBitmap(object);
          if (bitmap == nullptr) return false;
          late img.Image image;
          try {
            final format = pdf.FPDFBitmap_GetFormat(bitmap);
            // Reject alpha/masks, including apparently opaque BGRA bitmaps.
            if (format != 1 && format != 2 && format != 3) {
              count('alpha or unsupported bitmap');
              return false;
            }
            final width = pdf.FPDFBitmap_GetWidth(bitmap);
            final height = pdf.FPDFBitmap_GetHeight(bitmap);
            final stride = pdf.FPDFBitmap_GetStride(bitmap);
            final data = pdf.FPDFBitmap_GetBuffer(bitmap)
                .cast<Uint8>()
                .asTypedList(stride * height);
            image = img.Image.fromBytes(
              width: width,
              height: height,
              bytes: data.buffer,
              bytesOffset: data.offsetInBytes,
              rowStride: stride,
              numChannels: format == 1
                  ? 1
                  : format == 2
                  ? 3
                  : 4,
              order: format == 1
                  ? img.ChannelOrder.red
                  : format == 2
                  ? img.ChannelOrder.bgr
                  : img.ChannelOrder.bgra,
            ).convert(numChannels: 3);
          } finally {
            pdf.FPDFBitmap_Destroy(bitmap);
          }
          if (scale < 0.95) {
            image = img.copyResize(
              image,
              width: math.max(1, (image.width * scale).round()),
              height: math.max(1, (image.height * scale).round()),
              interpolation: img.Interpolation.average,
            );
          }
          final jpeg = img.encodeJpg(image, quality: quality);
          final previous = pdf.FPDFImageObj_GetImageDataRaw(object, nullptr, 0);
          // Never replace an image with a larger stream.
          if (previous <= jpeg.length) {
            count('replacement not smaller');
            return false;
          }
          final access = arena<native.FPDF_FILEACCESS>();
          final reader =
              NativeCallable<
                Int Function(
                  Pointer<Void>,
                  UnsignedLong,
                  Pointer<UnsignedChar>,
                  UnsignedLong,
                )
              >.isolateLocal((
                Pointer<Void> param,
                int position,
                Pointer<UnsignedChar> buffer,
                int size,
              ) {
                if (position + size > jpeg.length) return 0;
                buffer
                    .cast<Uint8>()
                    .asTypedList(size)
                    .setRange(0, size, jpeg, position);
                return 1;
              }, exceptionalReturn: 0);
          try {
            access.ref
              ..m_FileLen = jpeg.length
              ..m_GetBlock = reader.nativeFunction
              ..m_Param = nullptr;
            final pages = arena<native.FPDF_PAGE>();
            pages.value = page;
            if (pdf.FPDFImageObj_LoadJpegFileInline(pages, 1, object, access) ==
                0) {
              throw StateError('Could not replace embedded image.');
            }
          } finally {
            reader.close();
          }
          return true;
        });
        if (replaced) {
          changed++;
          dirty = true;
        }
      }
      if (dirty && pdf.FPDFPage_GenerateContent(page) == 0) {
        throw StateError('Could not regenerate image content.');
      }
    } finally {
      pdf.FPDF_ClosePage(page);
    }
  }
  stats['images changed'] = changed;
  return stats;
}
