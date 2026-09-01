import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GlassQualityMode { automatic, liquid, efficient }

/// Controls the renderer used by all glass surfaces.
///
/// Automatic mode uses the real Impeller shader only when the screen cost is
/// reasonable. Efficient mode bypasses both the shader and backdrop blur.
class GlassPerformanceController extends ChangeNotifier {
  GlassPerformanceController._();

  static final GlassPerformanceController instance =
      GlassPerformanceController._();

  static const _preferenceKey = 'liquid_glass_quality';
  GlassQualityMode _mode = GlassQualityMode.automatic;

  GlassQualityMode get mode => _mode;

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_preferenceKey);
    _mode = GlassQualityMode.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => GlassQualityMode.automatic,
    );
  }

  Future<void> setMode(GlassQualityMode value) async {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, value.name);
  }

  bool useLiquidGlass(BuildContext context) {
    switch (_mode) {
      case GlassQualityMode.liquid:
        return true;
      case GlassQualityMode.efficient:
        return false;
      case GlassQualityMode.automatic:
        final mediaQuery = MediaQuery.maybeOf(context);
        if (mediaQuery == null) return false;
        if (mediaQuery.disableAnimations) return false;

        // Shader cost scales with physical pixels. Very high-resolution
        // Android displays use the static surface in automatic mode unless
        // the user explicitly selects Liquid.
        final physicalPixels = mediaQuery.size.width *
            mediaQuery.devicePixelRatio *
            mediaQuery.size.height *
            mediaQuery.devicePixelRatio;
        if (defaultTargetPlatform == TargetPlatform.android) {
          return physicalPixels <= 3200000;
        }
        return true;
    }
  }
}

class _GlassRenderMode extends InheritedWidget {
  const _GlassRenderMode({
    required this.liquid,
    required super.child,
  });

  final bool liquid;

  static bool liquidOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassRenderMode>()?.liquid ??
      false;

  @override
  bool updateShouldNotify(_GlassRenderMode oldWidget) =>
      liquid != oldWidget.liquid;
}

class GlassScene extends StatelessWidget {
  const GlassScene({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = GlassPerformanceController.instance;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final useLiquid = controller.useLiquidGlass(context);
        final content = _GlassRenderMode(
          liquid: useLiquid,
          child: child,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            const RepaintBoundary(child: LiquidGlassBackdrop()),
            content,
          ],
        );
      },
    );
  }
}

LiquidGlassSettings glassSettingsFor({required bool dark}) {
  return LiquidGlassSettings(
    glassColor: dark ? const Color(0x24132A46) : const Color(0x24FFFFFF),
    thickness: 12,
    blur: dark ? 4 : 5,
    chromaticAberration: 0.0045,
    lightAngle: math.pi * 0.72,
    lightIntensity: dark ? 0.72 : 0.86,
    ambientStrength: dark ? 0.18 : 0.12,
    refractiveIndex: 1.12,
    saturation: dark ? 1.12 : 1.16,
  );
}

class LiquidGlassBackdrop extends StatelessWidget {
  const LiquidGlassBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [
                    Color(0xFF07111F),
                    Color(0xFF0B2237),
                    Color(0xFF10182B)
                  ]
                : const [
                    Color(0xFFF0F8FF),
                    Color(0xFFDDEFFF),
                    Color(0xFFF8F4FF)
                  ],
          ),
        ),
        child: CustomPaint(
          painter: _LiquidBackdropPainter(dark: dark),
        ),
      ),
    );
  }
}

class _LiquidBackdropPainter extends CustomPainter {
  const _LiquidBackdropPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    void orb(Offset center, double radius, List<Color> colors) {
      final paint = Paint()
        ..shader = RadialGradient(colors: colors).createShader(
          Rect.fromCircle(center: center, radius: radius),
        );
      canvas.drawCircle(center, radius, paint);
    }

    orb(
      Offset(size.width * 0.88, size.height * 0.1),
      size.shortestSide * 0.43,
      dark
          ? const [Color(0x884B72FF), Color(0x004B72FF)]
          : const [Color(0xAA78B8FF), Color(0x0078B8FF)],
    );
    orb(
      Offset(size.width * 0.08, size.height * 0.47),
      size.shortestSide * 0.38,
      dark
          ? const [Color(0x665BDBCE), Color(0x005BDBCE)]
          : const [Color(0x997FE8D6), Color(0x007FE8D6)],
    );
    orb(
      Offset(size.width * 0.82, size.height * 0.86),
      size.shortestSide * 0.34,
      dark
          ? const [Color(0x554E3D8D), Color(0x004E3D8D)]
          : const [Color(0x88D4A9FF), Color(0x00D4A9FF)],
    );

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = (dark ? Colors.white : const Color(0xFF386B9B))
          .withValues(alpha: dark ? 0.07 : 0.08);
    for (var i = 0; i < 5; i++) {
      final y = size.height * (0.19 + i * 0.16);
      final path = Path()..moveTo(-30, y);
      path.cubicTo(
        size.width * 0.26,
        y - 42,
        size.width * 0.68,
        y + 48,
        size.width + 30,
        y - 8,
      );
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidBackdropPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.tint,
    this.onTap,
    this.glow = false,
    this.stretch = false,
    this.grouped = false,
    this.liquid = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;
  final VoidCallback? onTap;
  final bool glow;
  final bool stretch;
  final bool grouped;

  /// Enables the expensive refraction shader for this surface in Liquid mode.
  /// Static cards intentionally keep this false to avoid scroll-time geometry
  /// updates; top bars, primary actions and dialogs opt in explicitly.
  final bool liquid;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final useLiquid = liquid && _GlassRenderMode.liquidOf(context);
    final edgeColor = Colors.white.withValues(alpha: dark ? 0.17 : 0.42);
    final shape = LiquidRoundedSuperellipse(
      borderRadius: radius,
      side: BorderSide(color: edgeColor, width: 0.85),
    );

    final surfaceAlpha =
        useLiquid ? (dark ? 0.08 : 0.16) : (dark ? 0.52 : 0.68);
    Widget content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: surfaceAlpha),
                (tint ?? (dark ? const Color(0xFF18324F) : Colors.white))
                    .withValues(alpha: useLiquid ? 0.07 : 0.38),
                (dark ? const Color(0xFF0C1D31) : const Color(0xFFEAF5FF))
                    .withValues(alpha: useLiquid ? 0.02 : 0.58),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.18 : 0.07),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );

    if (!useLiquid) return content;

    // Keep labels/icons out of the shader's render object. Only the empty
    // background shape is refracted; foreground content remains pixel-stable
    // while a scrollable list moves.
    Widget glassBackground = grouped
        ? LiquidGlass.grouped(
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: const SizedBox.expand(),
          )
        : LiquidGlass.withOwnLayer(
            shape: shape,
            settings: glassSettingsFor(dark: dark),
            clipBehavior: Clip.antiAlias,
            child: const SizedBox.expand(),
          );

    if (glow || onTap != null) {
      glassBackground = GlassGlow(
        glowColor: (tint ?? Colors.white).withValues(alpha: 0.2),
        child: glassBackground,
      );
    }

    Widget glass = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(child: glassBackground),
        ),
        content,
      ],
    );

    if (stretch && onTap != null) {
      glass = LiquidStretch(
        interactionScale: 0.992,
        stretch: 0.06,
        resistance: 0.16,
        child: glass,
      );
    }
    return glass;
  }
}

class GlassBlendGroup extends StatelessWidget {
  const GlassBlendGroup({
    required this.child,
    this.blend = 12,
    super.key,
  });

  final Widget child;
  final double blend;

  @override
  Widget build(BuildContext context) {
    if (!_GlassRenderMode.liquidOf(context)) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LiquidGlassLayer(
      settings: glassSettingsFor(dark: dark),
      child: LiquidGlassBlendGroup(blend: blend, child: child),
    );
  }
}

class GlassActionButton extends StatelessWidget {
  const GlassActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
    this.foregroundColor,
    this.height = 54,
    this.grouped = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? foregroundColor;
  final double height;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    final contentColor = foregroundColor ?? scheme.onSurface;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: GlassSurface(
          liquid: true,
          radius: height / 2,
          padding: EdgeInsets.zero,
          tint: accent,
          onTap: onPressed,
          glow: true,
          stretch: true,
          grouped: grouped,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: accent, size: 21),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: contentColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GlassTopBar extends StatelessWidget {
  const GlassTopBar({
    required this.title,
    this.leading,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      liquid: true,
      radius: 27,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            SizedBox(width: 44, child: leading),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
              ),
            ),
            SizedBox(width: 44, child: trailing),
          ],
        ),
      ),
    );
  }
}

InputDecoration glassInputDecoration(
  BuildContext context, {
  required String label,
  required IconData icon,
  String? hint,
}) {
  final scheme = Theme.of(context).colorScheme;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide(
      color: Colors.white.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.16 : 0.4,
      ),
    ),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon, size: 20),
    filled: true,
    fillColor: scheme.surface.withValues(alpha: 0.18),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: scheme.primary, width: 1.4),
    ),
    errorBorder: border.copyWith(
      borderSide: BorderSide(color: scheme.error, width: 1.2),
    ),
    focusedErrorBorder: border.copyWith(
      borderSide: BorderSide(color: scheme.error, width: 1.4),
    ),
  );
}

class LiquidGlassDialog extends StatelessWidget {
  const LiquidGlassDialog({
    required this.title,
    required this.content,
    required this.actions,
    super.key,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final controller = GlassPerformanceController.instance;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final useLiquid = controller.useLiquidGlass(context);
        Widget dialog = _GlassRenderMode(
          liquid: useLiquid,
          child: GlassSurface(
            liquid: true,
            radius: 30,
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle(
                    style: Theme.of(context).textTheme.titleLarge!.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    child: title,
                  ),
                  const SizedBox(height: 14),
                  DefaultTextStyle(
                    style: Theme.of(context).textTheme.bodyMedium!,
                    child: content,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions,
                  ),
                ],
              ),
            ),
          ),
        );
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: dialog,
            ),
          ),
        );
      },
    );
  }
}

Future<T?> showLiquidGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.24),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, _, __) => builder(context),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
