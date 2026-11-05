import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
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
  late final FixedExtentScrollController _daysController;
  late final FixedExtentScrollController _hoursController;
  late final FixedExtentScrollController _minutesController;

  int get _totalMinutes => _days * 1440 + _hours * 60 + _minutes;

  @override
  void initState() {
    super.initState();
    final total = widget.initial.inMinutes;
    _days = (total ~/ 1440).clamp(0, _maxDays).toInt();
    _hours = ((total % 1440) ~/ 60).clamp(0, 23).toInt();
    _minutes = (total % 60).clamp(0, 59).toInt();

    _daysController = FixedExtentScrollController(initialItem: _days);
    _hoursController = FixedExtentScrollController(initialItem: _hours);
    _minutesController = FixedExtentScrollController(initialItem: _minutes);
  }

  @override
  void dispose() {
    _daysController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalMinutes;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '提前提醒',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                total > 0 ? '将在截止前 ${formatReminderLead(total)}提醒' : '请选择提醒时间',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: total > 0 ? AppColors.accent : AppColors.muted,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 176,
                child: Row(
                  children: [
                    _buildWheel(
                      controller: _daysController,
                      count: _maxDays + 1,
                      unit: '天',
                      onChanged: (value) => setState(() => _days = value),
                    ),
                    _buildWheel(
                      controller: _hoursController,
                      count: 24,
                      unit: '小时',
                      onChanged: (value) => setState(() => _hours = value),
                    ),
                    _buildWheel(
                      controller: _minutesController,
                      count: 60,
                      unit: '分钟',
                      onChanged: (value) => setState(() => _minutes = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '提醒时间 = 作业截止时间 − 提前量',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(color: AppColors.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: total > 0
                          ? () => Navigator.of(
                              context,
                            ).pop(Duration(minutes: total))
                          : null,
                      child: const Text('确定导入'),
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

  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int count,
    required String unit,
    required ValueChanged<int> onChanged,
  }) {
    return Expanded(
      child: CupertinoPicker(
        scrollController: controller,
        itemExtent: 44,
        diameterRatio: 1.8,
        squeeze: 1,
        onSelectedItemChanged: (index) {
          HapticFeedback.selectionClick();
          onChanged(index);
        },
        selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
          background: AppColors.accent.withValues(alpha: 0.07),
          capStartEdge: false,
          capEndEdge: false,
        ),
        children: [
          for (var i = 0; i < count; i++)
            Center(
              child: Text(
                '$i $unit',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
