import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sickpdf/main.dart';
import 'package:sickpdf/screens/scan_document_page.dart';
import 'package:sickpdf/services/pdf_image_to_pdf_service.dart';
import 'package:sickpdf/services/scan_camera_gateway.dart';
import 'package:sickpdf/services/scan_crop_service.dart';
import 'package:sickpdf/services/scan_image_processor.dart';
import 'package:sickpdf/services/scan_service.dart';

/// Builds a small JPEG so the screen has real image bytes to show.
Uint8List _sampleJpeg({int width = 40, int height = 60}) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, 30, 120, 200, 255);
    }
  }
  return img.encodeJpg(image, quality: 80);
}

/// A camera gateway that never touches hardware.
class _FakeCamera implements ScanCameraGateway {
  _FakeCamera({
    this.openFailure,
    this.captureFailure,
    this.aspectRatio,
  });

  final ScanCameraException? openFailure;
  final ScanCameraException? captureFailure;

  /// What the fake camera reports for its preview aspect ratio.
  final double? aspectRatio;

  int pictureCount = 0;
  int openCount = 0;
  int closeCount = 0;
  bool closeCalled = false;

  @override
  bool get isReady => true;

  @override
  Widget? get preview => const SizedBox.shrink();

  @override
  double? get previewAspectRatio => aspectRatio;

  @override
  Future<void> open() async {
    openCount++;
    if (openFailure != null) throw openFailure!;
  }

  @override
  Future<Uint8List> takePicture() async {
    pictureCount++;
    if (captureFailure != null) throw captureFailure!;
    return _sampleJpeg();
  }

  @override
  Future<void> close() async {
    closeCount++;
    closeCalled = true;
  }
}

/// A cropper that either cancels or returns fixed bytes.
class _FakeCropper implements ScanCropService {
  _FakeCropper();

  int calls = 0;

  @override
  Future<Uint8List?> crop(Uint8List bytes) async {
    calls++;
    // The user always cancels in the widget tests.
    return null;
  }
}

/// An exporter that records the pages it was asked to convert.
class _FakeExporter extends PdfImageToPdfService {
  List<PdfImageInput>? lastImages;
  int calls = 0;

  @override
  Future<Uint8List> convert({
    required List<PdfImageInput> images,
    ImagePageSize size = ImagePageSize.a4,
    ImageMargin margin = ImageMargin.small,
    ImageFit fit = ImageFit.contain,
    double squareSide = 595.276,
  }) async {
    calls++;
    lastImages = images;
    return Uint8List.fromList([1, 2, 3]);
  }
}

/// An exporter that always fails, to exercise the error path.
class _FailingExporter extends PdfImageToPdfService {
  int calls = 0;

  @override
  Future<Uint8List> convert({
    required List<PdfImageInput> images,
    ImagePageSize size = ImagePageSize.a4,
    ImageMargin margin = ImageMargin.small,
    ImageFit fit = ImageFit.contain,
    double squareSide = 595.276,
  }) async {
    calls++;
    throw const PdfImageToPdfException('Not enough memory.');
  }
}

void main() {
  late _FakeCamera camera;
  late _FakeCropper cropper;
  late _FakeExporter exporter;

  setUp(() async {
    camera = _FakeCamera();
    cropper = _FakeCropper();
    exporter = _FakeExporter();
  });

  ScanDocumentService buildService({PdfImageToPdfService? exporterOverride}) =>
      ScanDocumentService(
        camera: camera,
        cropper: cropper,
        // The isolate is unavailable in the widget test environment, so the
        // pixel work runs inline.
        processor: const ScanImageProcessor(useIsolate: false),
        exporter: exporterOverride ?? exporter,
      );

  /// Opens the camera and captures [count] pages.
  Future<void> capturePages(WidgetTester tester, {int count = 1}) async {
    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();
    for (var i = 0; i < count; i++) {
      await tester.tap(find.text('Capture page'));
      await tester.pumpAndSettle();
    }
  }

  /// Drives the lifecycle through the exact sequence Android delivers when
  /// another activity (the native crop editor) comes to the front.
  ///
  /// Flutter asserts on invalid transitions, so `hidden` must not be skipped.
  Future<void> background(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
  }

  /// Drives the lifecycle back to the foreground.
  Future<void> foreground(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  /// Returns the [IconButton] whose tooltip is [tooltip].
  ///
  /// `find.byTooltip` matches the tooltip widget itself, so the button has
  /// to be looked up explicitly.
  IconButton iconButton(WidgetTester tester, String tooltip) {
    return tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      ),
    );
  }

  /// Scrolls the status area into view and returns its text.
  ///
  /// The status line sits at the bottom of a long list, so it is only built
  /// once the list is scrolled there.
  Future<String?> statusText(WidgetTester tester, String text) async {
    final finder = find.textContaining(text);
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    return tester.widget<Text>(finder.first).data;
  }

  testWidgets('Scan Document home tile opens the real workflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.dragUntilVisible(
      find.text('Scan Document'),
      find.byType(CustomScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan Document'));
    await tester.pumpAndSettle();

    expect(find.byType(ScanDocumentPage), findsOneWidget);
    expect(find.textContaining('coming soon'), findsNothing);
    // Without a camera the screen asks the user to open it first.
    expect(find.text('Open camera'), findsOneWidget);
    // No pages yet, so the export actions stay disabled.
    final save = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Save PDF'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('the camera opens on request and a page can be captured', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();

    await capturePages(tester);

    expect(camera.pictureCount, 1);
    expect(find.text('Page 1'), findsOneWidget);
    // The export actions appear once a page exists.
    expect(find.text('Preview PDF'), findsOneWidget);
    expect(find.text('Save PDF'), findsOneWidget);
  });

  testWidgets('a denied camera permission shows an actionable error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    camera = _FakeCamera(
      openFailure: const ScanCameraException(
        ScanCameraFailure.permissionDenied,
        'sickPDF needs the camera to scan a document. Enable it in the app '
            'settings, then try again.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();

    expect(find.textContaining('needs the camera'), findsOneWidget);
    expect(find.text('The camera is not available'), findsOneWidget);
    // The screen must not crash and must still offer a way forward.
    expect(find.text('Open camera'), findsOneWidget);
  });

  testWidgets('a failed capture is reported without losing the screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    camera = _FakeCamera(
      captureFailure: const ScanCameraException(
        ScanCameraFailure.captureFailed,
        'The photo could not be taken. Try again.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();

    await capturePages(tester);

    expect(find.textContaining('could not be taken'), findsOneWidget);
    expect(find.text('No pages captured yet.'), findsOneWidget);
  });

  testWidgets('the preview frame uses the camera reported ratio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // A 16:9 portrait sensor reports 9/16.
    camera = _FakeCamera(aspectRatio: 9 / 16);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();

    final frames = tester.widgetList<AspectRatio>(
      find.byType(AspectRatio),
    );
    expect(
      frames.any((f) => (f.aspectRatio - 9 / 16).abs() < 0.001),
      isTrue,
      reason: 'The frame should match the sensor, not a hard-coded 3:4.',
    );
    expect(
      frames.any((f) => (f.aspectRatio - 3 / 4).abs() < 0.001),
      isFalse,
      reason: 'The old hard-coded 3:4 ratio must be gone.',
    );
  });

  testWidgets('an unknown preview ratio falls back to a neutral frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // `aspectRatio: null` is what the fake reports by default.
    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();

    final frames = tester.widgetList<AspectRatio>(find.byType(AspectRatio));
    expect(
      frames.any((f) => (f.aspectRatio - 3 / 4).abs() < 0.001),
      isTrue,
      reason: 'A missing ratio must not collapse the layout.',
    );
  });

  testWidgets('an implausible preview ratio is ignored', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    camera = _FakeCamera(aspectRatio: 0);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();

    // A zero ratio would make AspectRatio throw or render nothing.
    expect(tester.takeException(), isNull);
    final frames = tester.widgetList<AspectRatio>(find.byType(AspectRatio));
    expect(
      frames.any((f) => (f.aspectRatio - 3 / 4).abs() < 0.001),
      isTrue,
    );
  });

  testWidgets('captured pages can be removed', (tester) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();

    await capturePages(tester, count: 2);

    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.textContaining('2 pages'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove page 1'));
    await tester.pumpAndSettle();

    // The remaining page is renumbered, so there is only a "Page 1" left.
    expect(find.textContaining('1 page •'), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsNothing);
  });

  testWidgets('pages can be reordered with the arrow buttons', (tester) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();

    await capturePages(tester, count: 2);

    // The first page can move down, the last one cannot.
    expect(iconButton(tester, 'Move page 1 down').onPressed, isNotNull);
    expect(iconButton(tester, 'Move page 2 down').onPressed, isNull);

    await tester.tap(find.byTooltip('Move page 1 down'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 pages'), findsOneWidget);
    // After the move the first page cannot move up any more.
    expect(iconButton(tester, 'Move page 1 up').onPressed, isNull);
    expect(iconButton(tester, 'Move page 2 up').onPressed, isNotNull);
  });

  testWidgets('a page can be retaken', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();

    await capturePages(tester);

    await tester.tap(find.byTooltip('Retake page 1'));
    await tester.pumpAndSettle();

    // The retake replaces the page instead of adding a second one.
    expect(camera.pictureCount, 2);
    expect(find.textContaining('1 page •'), findsOneWidget);
    expect(find.text('Page 2'), findsNothing);
  });

  testWidgets('the crop editor opens for a page and a cancel keeps the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();

    await capturePages(tester);

    await tester.tap(find.byTooltip('Crop page 1'));
    await tester.pumpAndSettle();

    // The crop editor opened at least once: the capture itself may already
    // have offered it when no edge could be detected.
    expect(cropper.calls, greaterThanOrEqualTo(1));
    expect(await statusText(tester, 'Crop cancelled'), isNotNull);
    // The page is still there.
    expect(find.text('Page 1'), findsOneWidget);
  });

  testWidgets('export fails with an actionable message when the PDF fails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final failing = _FailingExporter();

    await tester.pumpWidget(
      MaterialApp(
        home: ScanDocumentPage(
          service: buildService(exporterOverride: failing),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await capturePages(tester);

    await tester.tap(find.text('Save PDF'));
    await tester.pumpAndSettle();

    expect(failing.calls, 1);
    expect(await statusText(tester, 'Not enough memory'), isNotNull);
  });

  testWidgets('the export action is disabled until a page exists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();

    final save = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Save PDF'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('a second export tap cannot start a second export', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();

    await capturePages(tester);

    await tester.tap(find.text('Save PDF'));
    await tester.pump();
    // The second tap lands while the first export is still running.
    await tester.tap(find.text('Save PDF'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // The exporter is called once even though the button was tapped twice.
    expect(exporter.calls, 1);
  });

  testWidgets('going to the background releases the camera exactly once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();
    expect(camera.openCount, 1);

    // This is the sequence Android delivers while the UCrop activity is in
    // front: inactive, then paused.
    await background(tester);

    // Only one release, even though several lifecycle events arrived.
    expect(camera.closeCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning from the background reopens the camera once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();
    expect(camera.openCount, 1);

    // Leave for the crop editor, then come back.
    await background(tester);
    await foreground(tester);

    // Exactly one reopen: no double initialization.
    expect(camera.openCount, 2);
    expect(camera.closeCount, 1);
    expect(find.text('Capture page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resuming without a prior pause does not reopen the camera', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();

    // A spurious resumed must not churn the controller.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(camera.openCount, 1);
    expect(camera.closeCount, 0);
  });

  testWidgets('a background release before the camera opens is a no-op', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();

    await background(tester);

    // Nothing was open, so nothing is closed.
    expect(camera.closeCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pages survive a background round trip', (tester) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();
    await capturePages(tester, count: 2);
    expect(find.textContaining('2 pages'), findsOneWidget);

    await background(tester);
    await foreground(tester);

    // The captured pages must not be lost by the lifecycle cycle.
    expect(find.textContaining('2 pages'), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
  });

  testWidgets('the camera is released when the screen is closed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ScanDocumentPage(service: buildService())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();

    // Replace the screen so it is disposed.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();

    expect(camera.closeCalled, isTrue);
  });
}
