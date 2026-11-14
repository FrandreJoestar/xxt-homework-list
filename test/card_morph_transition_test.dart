import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xuexitong_homework/widgets/card_morph_transition.dart';

void main() {
  testWidgets('卡片拉伸过渡展开结束后按自然尺寸居中显示', (tester) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 280),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardMorphTransition(
            origin: const Rect.fromLTWH(20, 360, 320, 96),
            animation: controller,
            child: Container(
              width: 300,
              height: 320,
              color: const Color(0xFFEFEFEF),
            ),
          ),
        ),
      ),
    );
    // 首帧用于静默测量面板尺寸
    await tester.pump();
    await tester.pump();

    controller.forward();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final panel = find.byType(Container);
    expect(tester.getSize(panel), const Size(300, 320));
    // 默认测试画布 800x600，展开结束后面板应居中
    expect(tester.getCenter(panel), const Offset(400, 300));
  });

  testWidgets('卡片拉伸过渡反向收起不报错', (tester) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 280),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardMorphTransition(
            origin: const Rect.fromLTWH(20, 360, 320, 96),
            animation: controller,
            child: Container(
              width: 300,
              height: 320,
              color: const Color(0xFFEFEFEF),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    controller.forward();
    await tester.pumpAndSettle();
    controller.reverse();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  });
}
