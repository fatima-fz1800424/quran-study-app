import 'package:flutter/material.dart';

import 'decoration.dart';

/// Shared motion and depth tokens.
///
/// Two rules hold everywhere: nothing lasts longer than 240ms, and nothing
/// overshoots. The reader is for long-form reading, so movement is there to
/// explain a change, not to draw attention to itself.
class Motion {
  const Motion._();

  /// Icon and colour state changes.
  static const Duration quick = Duration(milliseconds: 140);

  /// The default: entrances, fades, elevation changes.
  static const Duration normal = Duration(milliseconds: 200);

  /// Only for the longest transition in the app, the tab change.
  static const Duration slow = Duration(milliseconds: 240);

  /// Decelerating, never overshooting. Bouncy curves read as playful, which is
  /// the wrong register here.
  static const Curve curve = Curves.easeOutCubic;

  /// Honour the platform's reduce-motion setting.
  ///
  /// On the web this follows `prefers-reduced-motion`. When it is set, every
  /// duration collapses to zero: state still changes, it simply arrives
  /// immediately instead of being animated.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration duration(BuildContext context, Duration base) =>
      reduced(context) ? Duration.zero : base;
}

/// Soft, low-opacity shadows used instead of borders.
///
/// Tuned per theme rather than shared: the same shadow that reads as a gentle
/// lift on warm paper disappears entirely on charcoal, so the dark variant is
/// deeper and tighter.
class Elevation {
  const Elevation._();

  static List<BoxShadow> resting(Brightness brightness) => brightness ==
          Brightness.light
      ? const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ];

  /// Pressed state: the shadow tightens and the surface moves closer to the
  /// page, which is what makes a tap feel acknowledged.
  static List<BoxShadow> pressed(Brightness brightness) => brightness ==
          Brightness.light
      ? const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x2E000000),
            blurRadius: 5,
            offset: Offset(0, 1),
          ),
        ];

  /// The reciting verse, lifted a little further off the page than a card.
  static List<BoxShadow> raised(Brightness brightness, Color accent) => [
        BoxShadow(
          color: accent.withOpacity(brightness == Brightness.light ? 0.20 : 0.28),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];
}

/// Fade and slide a child in once, the first time it is built.
///
/// Used for list items as they enter the viewport while scrolling. It runs once
/// per item and never repeats, so nothing moves while the reader is sitting
/// still and reading.
class EntranceFade extends StatefulWidget {
  const EntranceFade({
    required this.child,
    this.offset = 8,
    this.duration = Motion.normal,
    super.key,
  });

  final Widget child;

  /// Vertical travel in logical pixels. Deliberately small.
  final double offset;
  final Duration duration;

  @override
  State<EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<EntranceFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    // Started from a post-frame callback so the first frame is the pre-animation
    // state; starting during build would skip the fade entirely.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) {
      return widget.child;
    }
    final eased = CurvedAnimation(parent: _controller, curve: Motion.curve);
    return AnimatedBuilder(
      animation: eased,
      builder: (context, child) => Opacity(
        opacity: eased.value,
        child: Transform.translate(
          offset: Offset(0, (1 - eased.value) * widget.offset),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// A card that lowers slightly while pressed.
///
/// Wraps its own gesture handling rather than relying on InkWell, because the
/// feedback here is elevation rather than a ripple - a ripple over warm paper
/// reads as a smudge.
class PressableCard extends StatefulWidget {
  const PressableCard({
    required this.child,
    required this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 18,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final EdgeInsets padding;
  final double borderRadius;

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: Motion.duration(context, Motion.quick),
        curve: Motion.curve,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: _pressed
              ? Elevation.pressed(brightness)
              : Elevation.resting(brightness),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Briefly acknowledge a tap, then run [onComplete].
///
/// Used by citation chips: the chip dips before the reader is opened, so the
/// navigation reads as a consequence of the tap rather than an interruption.
class TapAcknowledge extends StatefulWidget {
  const TapAcknowledge({
    required this.child,
    required this.onComplete,
    super.key,
  });

  final Widget child;
  final VoidCallback onComplete;

  @override
  State<TapAcknowledge> createState() => _TapAcknowledgeState();
}

class _TapAcknowledgeState extends State<TapAcknowledge> {
  double _scale = 1;

  Future<void> _run() async {
    if (Motion.reduced(context)) {
      widget.onComplete();
      return;
    }
    setState(() => _scale = 0.94);
    await Future<void>.delayed(Motion.quick);
    if (!mounted) {
      return;
    }
    setState(() => _scale = 1);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _run,
      child: AnimatedScale(
        scale: _scale,
        duration: Motion.duration(context, Motion.quick),
        curve: Motion.curve,
        child: widget.child,
      ),
    );
  }
}

/// Identity gradients.
///
/// The light end is capped at #8E4FE8 deliberately: white body text on it
/// measures 4.74:1, and anything lighter drops below the 4.5:1 AA threshold.
/// The prettier, paler purple would have failed.
class AppGradients {
  const AppGradients._();

  static LinearGradient identity(Brightness brightness) =>
      brightness == Brightness.light
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7B3FE4), Color(0xFF8E4FE8)],
            )
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4A2A8A), Color(0xFF6A3FC0)],
            );

  /// Shadow tinted with the gradient, so a raised purple card does not look
  /// like it is casting a grey shadow onto warm paper.
  static List<BoxShadow> glow(Brightness brightness) => [
        BoxShadow(
          color: const Color(0xFF7B3FE4)
              .withOpacity(brightness == Brightness.light ? 0.28 : 0.36),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
}

/// A card carrying the identity gradient. Used for headers and the resume card,
/// never behind verse text.
///
/// Every one of these carries the eight-point star tiling, clipped to the
/// card's own radius and faded out towards the text. The opacity is set here
/// rather than left to callers so the ornament cannot drift louder in one place
/// than another: 7% white in light, 9% in dark, where the deeper gradient eats
/// more of it.
class GradientCard extends StatelessWidget {
  const GradientCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.patternTile = 58,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  /// Repeat size of the star tiling. Larger cards can carry a larger figure.
  final double patternTile;

  static const double radius = 22;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppGradients.identity(brightness),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppGradients.glow(brightness),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            Positioned.fill(
              child: PatternWash(
                color: Colors.white.withOpacity(
                  brightness == Brightness.light ? 0.07 : 0.09,
                ),
                tile: patternTile,
              ),
            ),
            Padding(
              padding: padding,
              child: SizedBox(width: double.infinity, child: child),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) {
      return card;
    }
    return _PressScale(onTap: onTap!, child: card);
  }
}

/// A small label pill for metadata on a gradient.
///
/// Frosted white with deep purple text rather than translucent white with white
/// text: the latter measures 3.49:1 on the gradient and fails AA.
class MetaPill extends StatelessWidget {
  const MetaPill(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF5F27C4),
        ),
      ),
    );
  }
}

/// A circled number badge, used for surah and verse numbers.
///
/// [diameter] carries the whole scale: the type size and the ring thickness are
/// derived from it, so the list badge and the reader header's much larger one
/// are the same object at two sizes rather than two similar-looking widgets.
class NumberBadge extends StatelessWidget {
  const NumberBadge(
    this.number, {
    this.onGradient = false,
    this.diameter = 38,
    this.ringed = false,
    super.key,
  });

  final int number;
  final bool onGradient;
  final double diameter;

  /// A thin concentric ring outside the disc. Only worth it at header size -
  /// on a 38px badge it just muddies the edge.
  final bool ringed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disc = Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onGradient
            ? Colors.white.withOpacity(0.95)
            : theme.colorScheme.primary.withOpacity(
                theme.brightness == Brightness.light ? 0.10 : 0.20,
              ),
      ),
      child: Text(
        '$number',
        style: TextStyle(
          fontSize: diameter * 0.36,
          fontWeight: FontWeight.w700,
          height: 1,
          color: onGradient
              ? const Color(0xFF5F27C4)
              : theme.colorScheme.primary,
        ),
      ),
    );

    if (!ringed) {
      return disc;
    }
    return Container(
      padding: EdgeInsets.all(diameter * 0.1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: onGradient
              ? Colors.white.withOpacity(0.4)
              : theme.colorScheme.primary.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: disc,
    );
  }
}

/// Shared press-scale used by gradient cards.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: Motion.duration(context, Motion.quick),
        curve: Motion.curve,
        child: widget.child,
      ),
    );
  }
}
