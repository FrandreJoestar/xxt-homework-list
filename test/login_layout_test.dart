import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xuexitong_homework/screens/login_screen.dart';
import 'package:xuexitong_homework/theme.dart';

Future<void> _pumpLogin(
  WidgetTester tester, {
  required Size physicalSize,
  required double devicePixelRatio,
  double keyboardInset = 0,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.viewInsets = FakeViewPadding(
    bottom: keyboardInset * devicePixelRatio,
  );
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MiuixTheme(
      data: buildMiuixTheme(),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: LoginScreen(onLoggedIn: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final exception = tester.takeException();
  if (exception != null) fail('$exception');
}

void main() {
  testWidgets('登录页在常见手机尺寸下不溢出', (tester) async {
    await _pumpLogin(
      tester,
      physicalSize: const Size(1080, 2400),
      devicePixelRatio: 3.0,
    );
  });

  testWidgets('登录页在小屏手机上不溢出', (tester) async {
    await _pumpLogin(
      tester,
      physicalSize: const Size(720, 1280),
      devicePixelRatio: 2.0,
    );
    await _pumpLogin(
      tester,
      physicalSize: const Size(1080, 1920),
      devicePixelRatio: 3.0,
    );
  });

  testWidgets('登录页弹出键盘时仍可滚动不溢出', (tester) async {
    await _pumpLogin(
      tester,
      physicalSize: const Size(1080, 2400),
      devicePixelRatio: 3.0,
      keyboardInset: 320,
    );
  });
}
