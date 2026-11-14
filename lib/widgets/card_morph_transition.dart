import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// 「卡片拉伸」式的路由过渡：把小卡片的矩形插值到目标面板的矩形。
///
/// 先把 [child] 按自然尺寸静默布局一帧量出大小，再把 [origin] 矩形插值到
/// 面板矩形；面板始终按最终尺寸布局，外层用随矩形变化的 [ClipRect] 逐步露出，
/// 视觉上就是原卡片被拉伸到新位置。动画结束时恢复自然布局，反向时沿同一路径收回。
class CardMorphTransition extends StatefulWidget {
  const CardMorphTransition({
    super.key,
    required this.origin,
    required this.animation,
    required this.child,
  });

  /// 被点击卡片在屏幕上的矩形；为 null 时不做位移，只做淡入。
  final Rect? origin;

  /// 目标路由的动画，通常来自 `showGeneralDialog` 的 `transitionBuilder`。
  final Animation<double> animation;

  /// 目标面板，会按自身内容尺寸布局。
  final Widget child;

  @override
  State<CardMorphTransition> createState() => _CardMorphTransitionState();
}

class _CardMorphTransitionState extends State<CardMorphTransition> {
  final GlobalKey _panelKey = GlobalKey();
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: widget.animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  Size? _panelSize;
  bool _morphing = true;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_handleStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_handleStatus);
    _curve.dispose();
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed && _morphing) {
      // 动画结束后恢复自然布局，内容后续改变高度时不会被裁切。
      setState(() => _morphing = false);
    } else if (status == AnimationStatus.reverse && !_morphing) {
      // 收起前重新量一次当前高度，避免从旧尺寸开始收。
      final size = _panelKey.currentContext?.size;
      setState(() {
        if (size != null) _panelSize = size;
        _morphing = true;
      });
    }
  }

  /// 首帧透明布局一次，拿到面板的自然尺寸作为插值终点。
  void _measure() {
    final size = _panelKey.currentContext?.size;
    if (size == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
      return;
    }
    if (size != _panelSize) setState(() => _panelSize = size);
  }

  Widget _panel(double maxWidth, double maxHeight) {
    return ConstrainedBox(
      key: _panelKey,
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      child: widget.child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final maxWidth = math.min(440.0, screen.width - 52);
    final maxHeight = screen.height - 64;
    final panel = _panel(maxWidth, maxHeight);

    final size = _panelSize;
    if (size == null) {
      // 还没量到尺寸：透明布局一帧，不拦截手势。
      return IgnorePointer(
        child: Opacity(opacity: 0, child: Center(child: panel)),
      );
    }
    if (!_morphing) {
      return Center(child: panel);
    }
    final target = Rect.fromCenter(
      center: screen.center(Offset.zero),
      width: size.width,
      height: size.height,
    );
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final t = _curve.value;
        final rect = Rect.lerp(widget.origin ?? target, target, t)!;
        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minWidth: size.width,
                  maxWidth: size.width,
                  minHeight: size.height,
                  maxHeight: size.height,
                  // 前 25% 淡入，避免刚推入时面板内容显得突兀。
                  child: Opacity(
                    opacity: (t / 0.25).clamp(0.0, 1.0),
                    child: panel,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
