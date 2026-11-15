import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// 「卡片本体变形」式的路由过渡。
///
/// 推入时把被点击卡片的矩形插值到目标面板矩形，卡片内容先淡出、面板内容
/// 在变形接近结束时再淡入，同时绘制背景遮罩让卡片看起来是悬浮的；
/// 关闭时沿同一路径收回卡片。
class CardMorphTransition extends StatefulWidget {
  const CardMorphTransition({
    super.key,
    required this.origin,
    required this.animation,
    required this.child,
    required this.sourceColor,
    required this.targetColor,
    this.source,
    this.cornerRadius = 16,
    this.targetCornerRadius = 28,
    this.scrimColor = const Color(0x8A000000),
  });

  /// 被点击卡片在屏幕上的矩形；为 null 时不做位移，只做淡入。
  final Rect? origin;

  /// 目标路由的动画，通常来自 `showGeneralDialog` 的 `transitionBuilder`。
  final Animation<double> animation;

  /// 目标面板，会按自身内容尺寸布局。
  final Widget child;

  /// 源卡片视觉（通常就是列表里的那张卡片），变形开始时淡出。
  final Widget? source;

  /// 变形起始的卡片底色。
  final Color sourceColor;

  /// 变形结束的面板底色。
  final Color targetColor;

  /// 卡片圆角。
  final double cornerRadius;

  /// 面板圆角。
  final double targetCornerRadius;

  /// 背景遮罩色，会随动画淡入。
  final Color scrimColor;

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

  static const List<BoxShadow> _surfaceShadow = [
    BoxShadow(color: Color(0x33000000), blurRadius: 26, offset: Offset(0, 12)),
  ];

  /// 点击遮罩关闭；已经在收起过程中时忽略，避免连续点击把下层页面也弹掉。
  void _dismiss() {
    if (widget.animation.status == AnimationStatus.reverse) return;
    Navigator.of(context).maybePop();
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

    // 遮罩只负责绘制；点击关闭由单独的透明手势层处理。
    final scrim = Positioned.fill(
      child: IgnorePointer(child: ColoredBox(color: widget.scrimColor)),
    );
    final dismissible = Positioned.fill(
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _dismiss),
    );

    if (!_morphing) {
      return Stack(
        children: [
          scrim,
          dismissible,
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    widget.targetCornerRadius,
                  ),
                  boxShadow: _surfaceShadow,
                ),
                child: panel,
              ),
            ),
          ),
        ],
      );
    }

    final target = Rect.fromCenter(
      center: screen.center(Offset.zero),
      width: size.width,
      height: size.height,
    );
    final source = widget.source;
    final origin = widget.origin;
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final progress = widget.animation.value;
        final t = _curve.value;
        final rect = Rect.lerp(origin ?? target, target, t)!;
        final radius =
            widget.cornerRadius +
            (widget.targetCornerRadius - widget.cornerRadius) * t;
        // 卡片内容先淡出，等变形接近结束再淡入面板内容。
        final sourceOpacity = (1 - progress / 0.22).clamp(0.0, 1.0);
        final contentOpacity = ((progress - 0.62) / 0.38).clamp(0.0, 1.0);
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Color.lerp(Colors.transparent, widget.scrimColor, t)!,
                ),
              ),
            ),
            dismissible,
            Positioned.fromRect(
              rect: rect,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      widget.sourceColor,
                      widget.targetColor,
                      t,
                    ),
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: _surfaceShadow,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (contentOpacity > 0)
                        Center(
                          child: Opacity(
                            opacity: contentOpacity,
                            child: SizedBox(
                              width: size.width,
                              height: size.height,
                              child: widget.child,
                            ),
                          ),
                        ),
                      if (source != null && origin != null && sourceOpacity > 0)
                        Center(
                          child: Opacity(
                            opacity: sourceOpacity,
                            child: SizedBox(
                              width: origin.width,
                              height: origin.height,
                              child: source,
                            ),
                          ),
                        ),
                    ],
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
