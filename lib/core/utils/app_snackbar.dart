import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/theme_extensions.dart';

void showAppSnackBar(BuildContext context, String message, {Color? color, SnackBarAction? action}) {
  final t = context.tRead;
  final c = color ?? t.accentSuccess;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message, style: TextStyle(color: c, fontSize: t.fontSize(11))),
    backgroundColor: const Color(0xFF0A1A0A),
    behavior: SnackBarBehavior.floating,
    action: action,
    duration: action != null ? const Duration(seconds: 6) : const Duration(seconds: 4),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: BorderSide(color: c.withValues(alpha: 0.3)),
    ),
  ));
}

void showErrorSnackBar(BuildContext context, String message) {
  final t = context.tRead;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message, style: TextStyle(color: t.accentDanger, fontSize: t.fontSize(11))),
    backgroundColor: const Color(0xFF1A0A0A),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: BorderSide(color: t.accentDanger.withValues(alpha: 0.3)),
    ),
  ));
}

/// A short-lived confirmation pinned to the top-centre of the screen.
///
/// Unlike [showAppSnackBar] this does not sit in the Scaffold's bottom slot,
/// so it never covers bottom action bars (e.g. the gallery viewer's toolbar).
/// The toast ignores pointer events and removes itself after [duration].
void showTopToast(
  BuildContext context,
  String message, {
  Color? color,
  IconData? icon,
  Duration duration = const Duration(milliseconds: 1800),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    showAppSnackBar(context, message, color: color);
    return;
  }
  final t = context.tRead;
  final c = color ?? t.accentSuccess;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _TopToast(
      message: message,
      color: c,
      icon: icon,
      fontSize: t.fontSize(11),
      duration: duration,
      onDone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _TopToast extends StatefulWidget {
  final String message;
  final Color color;
  final IconData? icon;
  final double fontSize;
  final Duration duration;
  final VoidCallback onDone;

  const _TopToast({
    required this.message,
    required this.color,
    required this.icon,
    required this.fontSize,
    required this.duration,
    required this.onDone,
  });

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.6),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _anim.forward();
    _timer = Timer(widget.duration, () async {
      if (!mounted) return;
      await _anim.reverse();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 16;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _anim,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1A0A),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: widget.color.withValues(alpha: 0.3)),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: widget.fontSize + 4, color: widget.color),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.message,
                        style: TextStyle(
                          color: widget.color,
                          fontSize: widget.fontSize,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
