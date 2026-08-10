import 'package:flutter/widgets.dart';

class ScreenScaler extends StatelessWidget {
  const ScreenScaler({
    super.key,
    required this.viewport,
    required this.child,
    this.fit = BoxFit.contain,
  });

  final Size viewport;
  final BoxFit fit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = _computeScale(constraints.biggest, viewport, fit);
        final scaled = Size(viewport.width * scale, viewport.height * scale);
        return Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            OverflowBox(
              minWidth: 0,
              maxWidth: scaled.width,
              minHeight: 0,
              maxHeight: scaled.height,
              alignment: Alignment.center,
              child: ScaledViewport(
                scale: scale,
                viewport: viewport,
                child: SizedBox(
                  width: viewport.width,
                  height: viewport.height,
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static double _computeScale(Size available, Size viewport, BoxFit fit) {
    if (available.isEmpty || viewport.isEmpty) return 1;
    return switch (fit) {
      BoxFit.contain => _min(available, viewport),
      BoxFit.fill => _min(available, viewport),
      BoxFit.cover => _max(available, viewport),
      BoxFit.fitWidth => available.width / viewport.width,
      BoxFit.fitHeight => available.height / viewport.height,
      BoxFit.none => 1,
      _ => _min(available, viewport),
    };
  }

  static double _min(Size available, Size viewport) {
    return (available.width / viewport.width < available.height / viewport.height)
        ? available.width / viewport.width
        : available.height / viewport.height;
  }

  static double _max(Size available, Size viewport) {
    return (available.width / viewport.width > available.height / viewport.height)
        ? available.width / viewport.width
        : available.height / viewport.height;
  }
}

class ScaledViewport extends InheritedWidget {
  const ScaledViewport({
    super.key,
    required this.scale,
    required this.viewport,
    required super.child,
  });

  final double scale;
  final Size viewport;

  static ScaledViewport? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ScaledViewport>();
  }

  static double scaleOf(BuildContext context) => maybeOf(context)?.scale ?? 1;
  static Size viewportOf(BuildContext context) =>
      maybeOf(context)?.viewport ?? Size.zero;

  Offset logicalToGlobal(BuildContext context, Offset logical) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return logical * scale;
    return box.localToGlobal(logical * scale);
  }

  @override
  bool updateShouldNotify(ScaledViewport oldWidget) {
    return scale != oldWidget.scale || viewport != oldWidget.viewport;
  }
}
