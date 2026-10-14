// ArcTV 27 — "Liquid Glass" surfaces in the style of tvOS 26/27. GPL-3.0-or-later.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Frosted, translucent glass with a specular edge. When [focused] it turns into the
/// bright tvOS focus plate and flips its content to dark.
class LiquidGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final bool focused;
  final Color? tint;
  final double? width;
  final double? height;

  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.padding = EdgeInsets.zero,
    this.blur = 22,
    this.focused = false,
    this.tint,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final fg = focused ? const Color(0xFF111114) : Colors.white;
    final base = tint;
    final colors = focused
        ? [Colors.white.withValues(alpha: 0.96), Colors.white.withValues(alpha: 0.84)]
        : base != null
            ? [base.withValues(alpha: 0.55), base.withValues(alpha: 0.30)]
            : [Colors.white.withValues(alpha: 0.20), Colors.white.withValues(alpha: 0.06)];

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: AnimatedContainer(
          width: width,
          height: height,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
            border: Border.all(color: Colors.white.withValues(alpha: focused ? 0.95 : 0.24), width: 1),
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: fg),
            child: DefaultTextStyle.merge(style: TextStyle(color: fg), child: child),
          ),
        ),
      ),
    );
  }
}

/// D-pad focusable glass control: lifts (scale + shadow) and lights up on focus.
class GlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final double focusScale;
  final double? width;
  final double? height;
  final Color? tint;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  const GlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    this.focusScale = 1.08,
    this.width,
    this.height,
    this.tint,
    this.onKeyEvent,
  });

  /// Circular icon button, the building block of the tvOS 27 top bar.
  factory GlassButton.icon({
    Key? key,
    required IconData icon,
    VoidCallback? onPressed,
    ValueChanged<bool>? onFocusChange,
    FocusNode? focusNode,
    bool autofocus = false,
    double size = 44,
    Color? tint,
    Color? iconColor,
  }) =>
      GlassButton(
        key: key,
        onPressed: onPressed,
        onFocusChange: onFocusChange,
        focusNode: focusNode,
        autofocus: autofocus,
        width: size,
        height: size,
        tint: tint,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(size / 2),
        focusScale: 1.15,
        child: Center(child: Icon(icon, size: size * 0.5, color: iconColor)),
      );

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _focused = false;

  void _press() => widget.onPressed?.call();

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _press()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => _press()),
      },
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        canRequestFocus: widget.onPressed != null || widget.onFocusChange != null,
        onKeyEvent: widget.onKeyEvent,
        onFocusChange: (f) {
          setState(() => _focused = f);
          widget.onFocusChange?.call(f);
        },
        child: GestureDetector(
          onTap: _press,
          child: AnimatedScale(
            scale: _focused ? widget.focusScale : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                boxShadow: _focused
                    ? const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10))]
                    : const [],
              ),
              child: LiquidGlass(
                focused: _focused,
                tint: widget.tint,
                width: widget.width,
                height: widget.height,
                borderRadius: widget.borderRadius,
                padding: widget.padding,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass dialog shell used by the AirPlay and smart-home settings sheets.
class GlassDialog extends StatelessWidget {
  final String title;
  final Widget child;
  final double width;

  const GlassDialog({super.key, required this.title, required this.child, this.width = 620});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.of(context).size.height * 0.88),
          child: LiquidGlass(
            blur: 36,
            tint: const Color(0xFF1C1C22),
            borderRadius: BorderRadius.circular(32),
            padding: const EdgeInsets.fromLTRB(32, 26, 32, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                Flexible(child: SingleChildScrollView(child: child)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
