import 'package:flutter_miuix/miuix.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart'
    as flutter_material
    show DefaultMaterialLocalizations, Material, MaterialType;
import 'package:material_ui/material_ui.dart';

import '../services/chaoxing_client.dart';
import '../services/session_store.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLoggedIn});

  final VoidCallback onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final SessionStore _store = SessionStore();
  late final ChaoxingClient _client = ChaoxingClient(_store);
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _client.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    if (phone.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入手机号与密码');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _client.login(phone, password);
      if (!mounted) return;
      widget.onLoggedIn();
    } on ChaoxingException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '登录失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    // MiuixScaffold 不会为键盘让位，这里手动把键盘高度计入滚动内容底部。
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return MiuixScaffold(
      containerColor: theme.colors.background,
      // flutter_miuix 的 MiuixTextField 内部用的是 Flutter 自带的 TextField，
      // 需要 flutter/material 的 Material 祖先与 MaterialLocalizations；
      // material_ui 的同名类属于另一套类型，无法满足该检查。
      content: (padding) => Localizations.override(
        context: context,
        delegates: const [
          flutter_material.DefaultMaterialLocalizations.delegate,
        ],
        child: flutter_material.Material(
          type: flutter_material.MaterialType.transparency,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  padding.top + 32,
                  24,
                  padding.bottom + 24 + keyboardInset,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        (constraints.maxHeight -
                                padding.vertical -
                                keyboardInset -
                                56)
                            .clamp(0.0, double.infinity),
                    maxWidth: 460,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BrandMark(theme: theme),
                      const SizedBox(height: 36),
                      MiuixText(
                        '登录学习通',
                        style: theme.textStyles.title1.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      MiuixText(
                        '读取你的课程作业与截止时间，\n一键同步到系统日历。',
                        style: theme.textStyles.body2.copyWith(height: 1.6),
                        color: theme.colors.onSurfaceVariantSummary,
                      ),
                      const SizedBox(height: 32),
                      _buildForm(theme),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MiuixIcon(
                            icon: Icons.lock_outline_rounded,
                            size: 14,
                            tint: theme.colors.onSurfaceVariantSummary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: MiuixText(
                              '账号与密码仅保存在本机，用于自动登录和读取作业；本应用只读，不会提交任何作业。',
                              style: theme.textStyles.footnote2.copyWith(
                                height: 1.5,
                              ),
                              color: theme.colors.onSurfaceVariantSummary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      MiuixText(
                        '© 2026 FrandreJoestar · 学习通作业本',
                        style: theme.textStyles.footnote2.copyWith(
                          letterSpacing: 0.3,
                        ),
                        color: theme.colors.onSurfaceVariantSummary,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildForm(MiuixThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MiuixTextField(
          controller: _phoneController,
          label: '手机号 / 学习通账号',
          singleLine: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          // MiuixTextField 会把图标槽直接贴着边框排，这里自己补内边距让图标往中间收。
          leadingIcon: const Padding(
            padding: EdgeInsets.only(left: 10, right: 8),
            child: MiuixIcon(icon: Icons.person_outline_rounded),
          ),
          insideMargin: const EdgeInsets.all(16),
        ),
        const SizedBox(height: 12),
        MiuixTextField(
          controller: _passwordController,
          label: '密码',
          singleLine: true,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          leadingIcon: const Padding(
            padding: EdgeInsets.only(left: 10, right: 8),
            child: MiuixIcon(icon: Icons.lock_outline_rounded),
          ),
          trailingIcon: Padding(
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: MiuixIconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              minWidth: 32,
              minHeight: 32,
              child: MiuixIcon(
                icon: _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
              ),
            ),
          ),
          insideMargin: const EdgeInsets.all(16),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          MiuixSurface(
            cornerRadius: 10,
            color: theme.colors.errorContainer,
            contentColor: theme.colors.onErrorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixIcon(
                    icon: Icons.error_outline_rounded,
                    size: 16,
                    tint: theme.colors.onErrorContainer,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: MiuixText(
                      _error!,
                      style: theme.textStyles.footnote2.copyWith(height: 1.4),
                      color: theme.colors.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: MiuixButton(
            onPressed: _submitting ? null : _submit,
            minHeight: 50,
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            child: _submitting
                ? const MiuixCircularProgressIndicator(
                    size: 18,
                    strokeWidth: 2,
                    colors: MiuixProgressIndicatorColors(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white70,
                      backgroundColor: Colors.white24,
                    ),
                  )
                : const MiuixText('登录'),
          ),
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.theme});

  final MiuixThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MiuixSurface(
          cornerRadius: 12,
          color: theme.colors.primary,
          contentColor: theme.colors.onPrimary,
          child: const SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: MiuixIcon(
                icon: Icons.assignment_turned_in_rounded,
                size: 22,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MiuixText(
              '学习通 · 作业本',
              style: theme.textStyles.body1.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 2),
            MiuixText(
              'DEADLINE TRACKER',
              style: theme.textStyles.footnote2.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6,
              ),
              color: theme.colors.onSurfaceVariantSummary,
            ),
          ],
        ),
      ],
    );
  }
}
