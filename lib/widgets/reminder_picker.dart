import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/reminder_text.dart';

/// 弹出提前提醒时间选择器，返回 null 表示取消。
Future<Duration?> showReminderPicker(
  BuildContext context, {
  Duration initial = const Duration(hours: 2),
}) {
  return showModalBottomSheet<Duration>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (context) => _ReminderPickerSheet(initial: initial),
  );
}

class _ReminderPickerSheet extends StatefulWidget {
  const _ReminderPickerSheet({required this.initial});

  final Duration initial;

  @override
  State<_ReminderPickerSheet> createState() => _ReminderPickerSheetState();
}

class _ReminderPickerSheetState extends State<_ReminderPickerSheet> {
  static const int _maxDays = 30;

  late int _days;
  late int _hours;
  late int _minutes;

  int get _totalMinutes => _days * 1440 + _hours * 60 + _minutes;

  @override
  void initState() {
    super.initState();
    final total = widget.initial.inMinutes;
    _days = (total ~/ 1440).clamp(0, _maxDays).toInt();
    _hours = ((total % 1440) ~/ 60).clamp(0, 23).toInt();
    _minutes = (total % 60).clamp(0, 59).toInt();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    final total = _totalMinutes;
    return Container(
      decoration: BoxDecoration(
        color: theme.colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colors.dividerLine,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              MiuixText(
                '提前提醒',
                style: theme.textStyles.title4.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              MiuixText(
                total > 0 ? '将在截止前 ${formatReminderLead(total)}提醒' : '请选择提醒时间',
                style: theme.textStyles.footnote1.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                color: total > 0
                    ? theme.colors.primary
                    : theme.colors.onSurfaceVariantSummary,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 176,
                child: Row(
                  children: [
                    Expanded(
                      child: MiuixNumberPicker(
                        value: _days,
                        min: 0,
                        max: _maxDays,
                        label: (value) => '$value 天',
                        visibleItemCount: 3,
                        itemHeight: 44,
                        onValueChanged: (value) =>
                            setState(() => _days = value),
                      ),
                    ),
                    Expanded(
                      child: MiuixNumberPicker(
                        value: _hours,
                        min: 0,
                        max: 23,
                        label: (value) => '$value 小时',
                        visibleItemCount: 3,
                        itemHeight: 44,
                        onValueChanged: (value) =>
                            setState(() => _hours = value),
                      ),
                    ),
                    Expanded(
                      child: MiuixNumberPicker(
                        value: _minutes,
                        min: 0,
                        max: 59,
                        label: (value) => '$value 分钟',
                        visibleItemCount: 3,
                        itemHeight: 44,
                        onValueChanged: (value) =>
                            setState(() => _minutes = value),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              MiuixText(
                '提醒时间 = 作业截止时间 − 提前量',
                style: theme.textStyles.footnote2,
                color: theme.colors.onSurfaceVariantSummary,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: MiuixTextButton(
                        '取消',
                        onPressed: () => Navigator.of(context).pop(),
                        minHeight: 50,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      width: double.infinity,
                      child: MiuixButton(
                        onPressed: total > 0
                            ? () => Navigator.of(
                                context,
                              ).pop(Duration(minutes: total))
                            : null,
                        minHeight: 50,
                        colors: MiuixButtonDefaults.buttonColorsPrimary(
                          context,
                        ),
                        child: const MiuixText('确定导入'),
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
