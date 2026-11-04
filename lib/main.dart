import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/homework_cache.dart';
import 'services/session_store.dart';
import 'theme.dart';

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
  bool _booting = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final hasCredentials = await _store.hasCredentials();
    if (!mounted) return;
    setState(() {
      _loggedIn = hasCredentials;
      _booting = false;
    });
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
    return MaterialApp(
      title: '学习通作业本',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: _booting
          ? const _BootScreen()
          : _loggedIn
          ? HomeScreen(onLoggedOut: _onLoggedOut)
          : LoginScreen(onLoggedIn: _onLoggedIn),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}
