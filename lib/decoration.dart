import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Code-drawn decoration: geometric patterns, ambient depth, and the About
/// screen's illustration.
///
/// Nothing here loads an asset. Every shape is a `Path` built at paint time,
/// which is deliberate - this app has already lost an audio source and a text
/// source to licence terms, and a downloaded ornament would be one more thing
/// to have to defend. A `CustomPainter` cannot be licensed away from us.

/// An interlaced eight-point star tiling, the `khatam` figure.
///
/// Each tile holds two squares sharing a centre, one turned 45 degrees against
/// the other; their overlap is the eight-point star. A smaller diamond sits on
/// every tile corner, where four stars meet, and that is what makes the grid
/// read as interlaced tilework rather than as loose stars.
///
/// Stroked only, never filled, and drawn in a single colour. Fills would give
/// the pattern a value of its own and it would start competing with the text
/// sitting on top of it.
class EightPointStarPattern extends CustomPainter {
  const EightPointStarPattern({
    required this.color,
    this.tile = 58,
    this.strokeWidth = 1,
  });

  final Color color;

  /// Edge length of one repeat. Smaller reads as texture, larger as ornament.
  final double tile;

  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || tile <= 0) {
      return;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    final radius = tile * 0.44;
    // A tile of overdraw on each side, so the tiling runs off the edges of the
    // card instead of stopping short of them.
    final columns = (size.width / tile).ceil() + 1;
    final rows = (size.height / tile).ceil() + 1;

    for (var row = -1; row < rows; row++) {
      for (var column = -1; column < columns; column++) {
        final centre = Offset((column + 0.5) * tile, (row + 0.5) * tile);
        canvas
          ..drawPath(_square(centre, radius, 0), paint)
          ..drawPath(_square(centre, radius, math.pi / 4), paint)
          ..drawPath(
            _square(
              centre + Offset(tile / 2, tile / 2),
              tile * 0.1,
              math.pi / 4,
            ),
            paint,
          );
      }
    }
  }

  /// A square as four points on a circle, so turning it is a single angle
  /// offset rather than a canvas transform.
  static Path _square(Offset centre, double radius, double rotation) {
    final path = Path();
    for (var corner = 0; corner < 4; corner++) {
      final angle = rotation + math.pi / 4 + corner * math.pi / 2;
      final point = Offset(
        centre.dx + radius * math.cos(angle),
        centre.dy + radius * math.sin(angle),
      );
      if (corner == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(EightPointStarPattern oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.tile != tile ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// The star tiling, faded across the card so it is densest in one corner and
/// gone by the opposite one.
///
/// The fade is what makes it usable behind text at all. A pattern held at one
/// flat opacity low enough to be safe under a headline is invisible in the
/// corners; ramping it lets the top-right carry visible ornament while the
/// side the text sits on stays clean.
class PatternWash extends StatelessWidget {
  const PatternWash({
    required this.color,
    this.tile = 58,
    this.begin = Alignment.topRight,
    this.end = Alignment.bottomLeft,
    super.key,
  });

  final Color color;
  final double tile;
  final Alignment begin;
  final Alignment end;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: begin,
          end: end,
          colors: const [Colors.white, Colors.transparent],
          stops: const [0.05, 0.85],
        ).createShader(bounds),
        child: CustomPaint(
          painter: EightPointStarPattern(color: color, tile: tile),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Soft translucent discs and a thin ring sitting behind a card.
///
/// Drawn deliberately outside the child's box - `Clip.none` plus negative
/// offsets - because the point is to suggest something *behind* the card, and a
/// glow that stops exactly at the card's edge just reads as part of the card.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    required this.child,
    this.tint,
    this.strength = 1,
    super.key,
  });

  final Widget child;

  /// Defaults to the theme's primary, so the glow is always the app's purple.
  final Color? tint;

  /// Multiplier on the base opacities, for places that want less of it.
  final double strength;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = tint ?? theme.colorScheme.primary;
    // Charcoal swallows a translucent wash, so the dark theme gets more of it.
    final base =
        (theme.brightness == Brightness.light ? 0.16 : 0.24) * strength;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          right: -30,
          top: -34,
          child: _Disc(diameter: 118, color: tone.withOpacity(base)),
        ),
        Positioned(
          left: -38,
          bottom: -30,
          child: _Disc(diameter: 92, color: tone.withOpacity(base * 0.7)),
        ),
        Positioned(
          left: -16,
          top: -24,
          child: _Ring(
            diameter: 70,
            color: tone.withOpacity(base * 0.9),
            strokeWidth: 1.4,
          ),
        ),
        child,
      ],
    );
  }
}

/// A disc that fades to nothing at its rim, so it has no visible edge.
class _Disc extends StatelessWidget {
  const _Disc({required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withOpacity(0)],
            stops: const [0.35, 1],
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.diameter,
    required this.color,
    required this.strokeWidth,
  });

  final double diameter;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: strokeWidth),
        ),
      ),
    );
  }
}

/// An open mushaf, drawn as paths.
///
/// Two leaves meeting at a spine, a suggestion of page thickness under each,
/// abstract rules standing in for lines of text, and an eight-point star
/// medallion above the spine. The rules are plain strokes and carry no script:
/// the app renders Quranic Arabic only from the verified corpus, and that holds
/// for ornament as much as for the reader.
class MushafIllustration extends StatelessWidget {
  const MushafIllustration({this.height = 176, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _MushafPainter(
          ink: theme.colorScheme.primary,
          wash: theme.colorScheme.primary.withOpacity(
            theme.brightness == Brightness.light ? 0.09 : 0.16,
          ),
        ),
      ),
    );
  }
}

class _MushafPainter extends CustomPainter {
  const _MushafPainter({required this.ink, required this.wash});

  final Color ink;
  final Color wash;

  /// The drawing is authored in this box and scaled to fit, so every number
  /// below can stay a plain readable coordinate.
  static const Size _design = Size(268, 186);
  static const double _spine = 134;

  /// Reflection in the spine, so the right leaf is the left one mirrored and
  /// the silhouette is symmetrical by construction rather than by hand.
  static final Float64List _mirror = (Matrix4.identity()
        ..translateByDouble(2 * _spine, 0, 0, 1)
        ..scaleByDouble(-1, 1, 1, 1))
      .storage;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final scale = math.min(
      size.width / _design.width,
      size.height / _design.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - _design.width * scale) / 2,
      (size.height - _design.height * scale) / 2,
    );
    canvas.scale(scale);

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = ink;
    final fill = Paint()..color = wash;

    final leftLeaf = _leaf();
    final rightLeaf = leftLeaf.transform(_mirror);

    // The page stack first, so each leaf sits on top of its own edges.
    _drawEdgeStack(canvas, mirrored: false);
    _drawEdgeStack(canvas, mirrored: true);

    canvas.drawPath(leftLeaf, fill);
    canvas.drawPath(rightLeaf, fill);
    _drawRules(canvas, leftLeaf, mirrored: false);
    _drawRules(canvas, rightLeaf, mirrored: true);
    canvas.drawPath(leftLeaf, outline);
    canvas.drawPath(rightLeaf, outline);

    // The spine last, so neither leaf's fill covers it.
    canvas.drawLine(
      const Offset(_spine, 54),
      const Offset(_spine, 152),
      outline,
    );

    _drawMedallion(canvas);
    canvas.restore();
  }

  /// The left leaf of the open book: up from the spine, out along the top edge,
  /// down the outer edge, and back to the spine along the page block.
  Path _leaf() {
    return Path()
      ..moveTo(_spine, 54)
      ..cubicTo(108, 40, 62, 32, 22, 46)
      ..lineTo(22, 128)
      ..cubicTo(64, 116, 108, 132, _spine, 152)
      ..close();
  }

  /// Two thinning repeats of the lower edge, offset downwards: the pages under
  /// the one being read.
  void _drawEdgeStack(Canvas canvas, {required bool mirrored}) {
    for (var layer = 1; layer <= 2; layer++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = ink.withOpacity(0.34 / layer);
      final edge = Path()
        ..moveTo(22, 128 + layer * 5)
        ..cubicTo(
          64,
          116 + layer * 5,
          108,
          132 + layer * 5,
          _spine,
          152 + layer * 4,
        );
      canvas.drawPath(mirrored ? edge.transform(_mirror) : edge, paint);
    }
  }

  /// Abstract rules of text, clipped to the leaf so none of them can escape
  /// its curved edges.
  void _drawRules(Canvas canvas, Path leaf, {required bool mirrored}) {
    canvas.save();
    canvas.clipPath(leaf);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..color = ink.withOpacity(0.3);

    // Ragged at the spine, even at the outer margin: how a column of set text
    // actually looks, without pretending to be text.
    const insets = <double>[0, 14, 4, 22, 8];
    for (var line = 0; line < insets.length; line++) {
      final y = 66 + line * 15.0;
      const outer = 34.0;
      final inner = _spine - 20 - insets[line];
      canvas.drawLine(
        Offset(mirrored ? 2 * _spine - outer : outer, y),
        Offset(mirrored ? 2 * _spine - inner : inner, y),
        paint,
      );
    }
    canvas.restore();
  }

  /// An eight-point star over the spine, ringed, marking the top of the book.
  void _drawMedallion(Canvas canvas) {
    const centre = Offset(_spine, 26);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..color = ink;

    canvas
      ..drawPath(EightPointStarPattern._square(centre, 15, 0), stroke)
      ..drawPath(EightPointStarPattern._square(centre, 15, math.pi / 4), stroke)
      ..drawCircle(centre, 3.4, Paint()..color = ink)
      ..drawCircle(
        centre,
        23,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = ink.withOpacity(0.35),
      );
  }

  @override
  bool shouldRepaint(_MushafPainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.wash != wash;
}
