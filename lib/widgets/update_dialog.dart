import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import '../services/update_service.dart';

/// 弹出更新提示；用户点击「去更新」时用浏览器打开安装包下载地址。
Future<void> showUpdateDialog(BuildContext context, AppUpdate update) {
  return showDialog<void>(
    context: context,
    builder: (context) => _UpdateDialog(update: update),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update});

  final AppUpdate update;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _opening = false;
  String? _error;

  Future<void> _openDownload() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    final opened = await UpdateService.openDownload(widget.update);
    if (!mounted) return;
    if (opened) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _opening = false;
      _error = '无法打开浏览器，请手动访问下面的下载地址';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final update = widget.update;
    return Dialog(
      backgroundColor: theme.colors.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MiuixSurface(
                    cornerRadius: 18,
                    color: theme.colors.primary.withValues(alpha: 0.12),
                    contentColor: theme.colors.primary,
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Center(
                        child: MiuixIcon(
                          icon: Icons.system_update_rounded,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  MiuixText(
                    '发现新版本',
                    style: theme.textStyles.footnote1.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    color: theme.colors.primary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              MiuixText(
                'v${update.version}',
                style: theme.textStyles.title2.copyWith(
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              MiuixText(
                '当前版本 v${update.currentVersion}，更新后可获得最新功能与修复。',
                style: theme.textStyles.footnote1.copyWith(height: 1.5),
                color: theme.colors.onSurfaceVariantSummary,
              ),
              const SizedBox(height: 14),
              const MiuixHorizontalDivider(),
              const SizedBox(height: 12),
              if (_error != null) ...[
                MiuixSurface(
                  cornerRadius: 10,
                  color: theme.colors.errorContainer,
                  contentColor: theme.colors.onErrorContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: MiuixText(
                      _error!,
                      style: theme.textStyles.footnote2.copyWith(height: 1.45),
                      color: theme.colors.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  update.downloadUrl,
                  style: theme.textStyles.footnote2.copyWith(
                    height: 1.4,
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              MiuixText(
                '将打开浏览器下载 APK；若下载失败，可稍后重试或更换网络。',
                style: theme.textStyles.footnote2.copyWith(height: 1.45),
                color: theme.colors.onSurfaceVariantSummary,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: MiuixTextButton(
                        '稍后',
                        onPressed: _opening
                            ? null
                            : () => Navigator.of(context).pop(),
                        minHeight: 48,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      width: double.infinity,
                      child: MiuixButton(
                        onPressed: _opening ? null : _openDownload,
                        minHeight: 48,
                        colors: MiuixButtonDefaults.buttonColorsPrimary(
                          context,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_opening)
                              const MiuixCircularProgressIndicator(
                                size: 18,
                                strokeWidth: 2,
                                colors: MiuixProgressIndicatorColors(
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor: Colors.white70,
                                  backgroundColor: Colors.white24,
                                ),
                              )
                            else
                              const MiuixIcon(
                                icon: Icons.open_in_browser_rounded,
                                size: 18,
                              ),
                            const SizedBox(width: 6),
                            MiuixText(_opening ? '正在打开…' : '去更新'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
