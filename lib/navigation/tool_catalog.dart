import 'package:flutter/material.dart';

import '../screens/add_text_pdf_page.dart';
import '../theme/app_theme.dart';
import '../screens/compress_pdf_page.dart';
import '../screens/images_to_pdf_page.dart';
import '../screens/ocr_pdf_page.dart';
import '../screens/organize_pdf_page.dart';
import '../screens/page_numbers_pdf_page.dart';
import '../screens/protect_pdf_page.dart';
import '../screens/rotate_pdf_page.dart';
import '../screens/sign_pdf_page.dart';
import '../screens/split_pdf_page.dart';
import '../screens/unlock_pdf_page.dart';
import '../screens/merge_pdf_page.dart';
import '../screens/watermark_pdf_page.dart';

/// A single entry point into an implemented tool. Every tool in the app is
/// described here so Home and Tools stay in sync and no feature is hidden.
class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.icon,
    required this.builder,
    required this.group,
    this.accent,
  });

  final String name;
  final String description;
  final IconData icon;
  final WidgetBuilder builder;
  final ToolGroup group;

  /// Optional muted accent color used to tint the tool's icon tile.
  /// Derived from the tool's [group] when null.
  final Color? accent;

  /// Muted accent color for this tool, falling back to its group's tint.
  Color effectiveAccent() => accent ?? group.accent;

  /// A single, consistent Material icon family is used everywhere.
  MaterialPageRoute<void> route() =>
      MaterialPageRoute<void>(builder: builder, settings: RouteSettings(name: name));
}

/// Logical grouping so first-time users can scan the tool list quickly.
enum ToolGroup {
  combineOrganize('Combine & organize'),
  convert('Convert'),
  edit('Edit & annotate'),
  secure('Secure');

  const ToolGroup(this.label);
  final String label;

  /// One muted tint per group, used for icon tiles.
  Color get accent => switch (this) {
        ToolGroup.combineOrganize => AppColors.teal,
        ToolGroup.convert => AppColors.success,
        ToolGroup.edit => const Color(0xFFB07A2A), // muted amber
        ToolGroup.secure => AppColors.danger,
      };
}

/// The canonical, ordered list of implemented tools.
const List<ToolDefinition> kTools = <ToolDefinition>[
  ToolDefinition(
    name: 'Merge PDF',
    description: 'Combine several PDFs into one, in your chosen order.',
    icon: Icons.merge_type,
    group: ToolGroup.combineOrganize,
    builder: _mergeBuilder,
  ),
  ToolDefinition(
    name: 'Split PDF',
    description: 'Extract a page range into a new PDF.',
    icon: Icons.call_split,
    group: ToolGroup.combineOrganize,
    builder: _splitBuilder,
  ),
  ToolDefinition(
    name: 'Organize PDF',
    description: 'Reorder, rotate and remove pages.',
    icon: Icons.reorder,
    group: ToolGroup.combineOrganize,
    builder: _organizeBuilder,
  ),
  ToolDefinition(
    name: 'Compress PDF',
    description: 'Shrink file size while keeping the original.',
    icon: Icons.compress,
    group: ToolGroup.convert,
    builder: _compressBuilder,
  ),
  ToolDefinition(
    name: 'Image to PDF',
    description: 'Turn photos and images into a PDF.',
    icon: Icons.image_outlined,
    group: ToolGroup.convert,
    builder: _imagesBuilder,
  ),
  ToolDefinition(
    name: 'OCR PDF',
    description: 'Read a scanned PDF and export the text.',
    icon: Icons.document_scanner_outlined,
    group: ToolGroup.convert,
    builder: _ocrBuilder,
  ),
  ToolDefinition(
    name: 'Rotate PDF',
    description: 'Rotate selected pages by 90°.',
    icon: Icons.rotate_right,
    group: ToolGroup.edit,
    builder: _rotateBuilder,
  ),
  ToolDefinition(
    name: 'Add Text to PDF',
    description: 'Place a text label on one or every page.',
    icon: Icons.text_fields,
    group: ToolGroup.edit,
    builder: _addTextBuilder,
  ),
  ToolDefinition(
    name: 'Watermark PDF',
    description: 'Stamp repeated text across pages.',
    icon: Icons.water_drop_outlined,
    group: ToolGroup.edit,
    builder: _watermarkBuilder,
  ),
  ToolDefinition(
    name: 'Page Numbers PDF',
    description: 'Add page numbers with position and format.',
    icon: Icons.pin_outlined,
    group: ToolGroup.edit,
    builder: _pageNumbersBuilder,
  ),
  ToolDefinition(
    name: 'Sign PDF',
    description: 'Draw and place a signature on a page.',
    icon: Icons.draw_outlined,
    group: ToolGroup.edit,
    builder: _signBuilder,
  ),
  ToolDefinition(
    name: 'Protect PDF',
    description: 'Encrypt a PDF with a password.',
    icon: Icons.lock_outline,
    group: ToolGroup.secure,
    builder: _protectBuilder,
  ),
  ToolDefinition(
    name: 'Unlock PDF',
    description: 'Remove the open password from a PDF.',
    icon: Icons.lock_open_outlined,
    group: ToolGroup.secure,
    builder: _unlockBuilder,
  ),
];

Widget _mergeBuilder(BuildContext context) => const MergePdfPage();
Widget _splitBuilder(BuildContext context) => const SplitPdfPage();
Widget _organizeBuilder(BuildContext context) => const OrganizePdfPage();
Widget _compressBuilder(BuildContext context) => const CompressPdfPage();
Widget _imagesBuilder(BuildContext context) => const ImagesToPdfPage();
Widget _ocrBuilder(BuildContext context) => const OcrPdfPage();
Widget _rotateBuilder(BuildContext context) => const RotatePdfPage();
Widget _addTextBuilder(BuildContext context) => const AddTextPdfPage();
Widget _watermarkBuilder(BuildContext context) => const WatermarkPdfPage();
Widget _pageNumbersBuilder(BuildContext context) => const PageNumbersPdfPage();
Widget _signBuilder(BuildContext context) => const SignPdfPage();
Widget _protectBuilder(BuildContext context) => const ProtectPdfPage();
Widget _unlockBuilder(BuildContext context) => const UnlockPdfPage();

/// Tools grouped for display, preserving [ToolGroup] declaration order.
///
/// Computed once and reused so Home/Tools do not rebuild the grouping on
/// every frame.
final Map<ToolGroup, List<ToolDefinition>> kGroupedTools =
    <ToolGroup, List<ToolDefinition>>{
      for (final group in ToolGroup.values)
        if (kTools.any((tool) => tool.group == group))
          group: kTools.where((tool) => tool.group == group).toList(),
    };
