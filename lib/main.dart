import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/homework_cache.dart';
import 'services/session_store.dart';
import 'services/update_service.dart';
import 'theme.dart';
import 'widgets/update_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XuexitongApp());
}

class XuexitongApp extends StatefulWidget {
  const XuexitongApp({super.key});

  @override
  State<XuexitongApp> createState() => _XuexitongAppState();
}

class _XuexitongAppState extends State<XuexitongApp> {
  final SessionStore _store = SessionStore();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _booting = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _boot();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _boot() async {
    final hasCredentials = await _store.hasCredentials();
    if (!mounted) return;
    setState(() {
      _loggedIn = hasCredentials;
      _booting = false;
    });
  }

  /// 每次启动静默检查 GitHub Release 上的 version.json，有新版本时弹窗。
  Future<void> _checkForUpdate() async {
    final update = await UpdateService.checkForUpdate();
    if (!mounted || update == null) return;
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await showUpdateDialog(context, update);
  }

  void _onLoggedIn() {
    setState(() => _loggedIn = true);
  }

  Future<void> _onLoggedOut() async {
    await _store.clear();
    await HomeworkCache().clear();
    if (!mounted) return;
    setState(() => _loggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    return MiuixTheme(
      data: buildMiuixTheme(),
      child: MaterialApp(
        title: '学习通作业本',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        theme: buildAppTheme(),
        // 没有 Material 祖先时，Text 会继承 DefaultTextStyle.fallback 的黄色双下划线；
        // 这里统一给全局文本一个 Miuix 基础样式。
        builder: (context, child) => DefaultTextStyle(
          style: MiuixTheme.of(context).textStyles.main,
          child: child ?? const SizedBox.shrink(),
        ),
        home: _booting
            ? const _BootScreen()
            : _loggedIn
            ? HomeScreen(onLoggedOut: _onLoggedOut)
            : LoginScreen(onLoggedIn: _onLoggedIn),
      ),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixScaffold(
      containerColor: theme.colors.background,
      content: (padding) => const Center(
        child: MiuixCircularProgressIndicator(size: 22, strokeWidth: 2.4),
      ),
    );
  }
}
