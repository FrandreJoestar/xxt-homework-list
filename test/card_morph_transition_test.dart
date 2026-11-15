import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xuexitong_homework/widgets/card_morph_transition.dart';

Widget _buildTransition(AnimationController controller) {
  return MaterialApp(
    home: Scaffold(
      body: CardMorphTransition(
        origin: const Rect.fromLTWH(20, 360, 320, 96),
        animation: controller,
        source: Container(color: const Color(0xFFFFFFFF)),
        sourceColor: const Color(0xFFFFFFFF),
        targetColor: const Color(0xFFF5F6F7),
        child: Container(
          width: 300,
          height: 320,
          color: const Color(0xFFEFEFEF),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('卡片变形结束后按自然尺寸居中显示，并保留背景遮罩', (tester) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 320),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_buildTransition(controller));
    // 首帧用于静默测量面板尺寸
    await tester.pump();
    await tester.pump();

    controller.forward();
    await tester.pump();
    // 动画起点应该正好是被点击卡片的矩形
    expect(
      tester.getRect(find.byType(Container).first),
      const Rect.fromLTWH(20, 360, 320, 96),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final panel = find.byType(Container).last;
    expect(tester.getSize(panel), const Size(300, 320));
    // 默认测试画布 800x600，变形结束后面板应居中
    expect(tester.getCenter(panel), const Offset(400, 300));
    // 面板后面应有半透明遮罩，让卡片看起来悬浮
    expect(find.byType(ColoredBox), findsWidgets);
  });

  testWidgets('卡片变形反向收起不报错', (tester) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 320),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_buildTransition(controller));
    await tester.pump();
    await tester.pump();

    controller.forward();
    await tester.pumpAndSettle();
    controller.reverse();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  });
}
