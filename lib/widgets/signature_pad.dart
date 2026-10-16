import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A single freehand stroke made of sampled offset points.
class _Stroke {
  _Stroke(this.points, this.width);
  final List<Offset> points;
  final double width;
}

/// Finger/stylus signature canvas with clear + transparent PNG export.
///
/// Strokes are stored as point lists and rendered with quadratic smoothing so
/// the exported image keeps the same smooth appearance as the on-screen ink.
class SignaturePad extends StatefulWidget {
  const SignaturePad({
    super.key,
    this.controller,
    this.height = 220,
    this.strokeWidth = 3.0,
    this.inkColor = Colors.black,
  });

  final SignaturePadController? controller;
  final double height;
  final double strokeWidth;
  final Color inkColor;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final _strokes = <_Stroke>[];
  _Stroke? _active;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant SignaturePad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }

  bool get isEmpty => _strokes.isEmpty && _active == null;

  void clear() {
    setState(() {
      _strokes.clear();
      _active = null;
    });
  }

  void _start(Offset point) {
    setState(() {
      _active = _Stroke([point], widget.strokeWidth);
      _strokes.add(_active!);
    });
  }

  void _extend(Offset point) {
    final active = _active;
    if (active == null) return;
    setState(() => active.points.add(point));
  }

  void _end() {
    // Drop accidental single taps that carry no visible stroke.
    if (_active != null && _active!.points.length < 2) {
      setState(() => _strokes.remove(_active));
    }
    _active = null;
  }

  /// Renders the strokes to a transparent-background PNG.
  ///
  /// Returns null when the pad is empty so callers can show a clear error
  /// instead of embedding a blank image.
  Future<Uint8List?> exportPng({double pixelRatio = 3.0}) async {
    if (isEmpty || _size.width <= 0 || _size.height <= 0) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..color = widget.inkColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final stroke in _strokes) {
      paint.strokeWidth = stroke.width;
      _paintStroke(canvas, stroke.points, paint);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (_size.width * pixelRatio).round(),
      (_size.height * pixelRatio).round(),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, widget.height);
        return GestureDetector(
          onPanStart: (details) => _start(details.localPosition),
          onPanUpdate: (details) => _extend(details.localPosition),
          onPanEnd: (_) => _end(),
          // Stylus/trackpad support and a stable pointer for taps.
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8EDF2)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CustomPaint(
                size: Size.infinite,
                painter: _SignaturePainter(
                  strokes: List.unmodifiable(_strokes),
                  color: widget.inkColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// External handle so a parent screen can read, clear and export the pad.
class SignaturePadController extends ChangeNotifier {
  _SignaturePadState? _state;

  void _attach(_SignaturePadState state) => _state = state;
  void _detach(_SignaturePadState state) {
    if (identical(_state, state)) _state = null;
  }

  bool get isEmpty => _state?.isEmpty ?? true;
  bool get hasSignature => !isEmpty;

  void clear() {
    _state?.clear();
    notifyListeners();
  }

  Future<Uint8List?> exportPng() async => _state?.exportPng();
}

/// Paints smooth strokes using quadratic interpolation between midpoints.
void _paintStroke(Canvas canvas, List<Offset> points, Paint paint) {
  if (points.isEmpty) return;
  if (points.length == 1) {
    canvas.drawCircle(points.first, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
    return;
  }
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 1; i < points.length - 1; i++) {
    final current = points[i];
    final next = points[i + 1];
    final mid = Offset((current.dx + next.dx) / 2, (current.dy + next.dy) / 2);
    path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  canvas.drawPath(path, paint);
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({required this.strokes, required this.color});
  final List<_Stroke> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final stroke in strokes) {
      paint.strokeWidth = stroke.width;
      _paintStroke(canvas, stroke.points, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.color != color;
}
