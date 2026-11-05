import 'package:flutter/services.dart';

import '../models/homework.dart';
import '../utils/reminder_text.dart';

class CalendarAddResult {
  final int added;
  final int skipped;
  final int failed;

  const CalendarAddResult({this.added = 0, this.skipped = 0, this.failed = 0});
}

/// 调用 Android 原生日历：申请读写日历权限，并按指定提前量设置提醒。
class CalendarService {
  static const MethodChannel _channel = MethodChannel(
    'com.frandre.homework_list/calendar',
  );

  /// 申请（或检查）日历读写权限，返回是否已获得。
  static Future<bool> ensurePermission() async {
    try {
      return await _channel.invokeMethod<bool>('ensurePermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 为作业创建日程：事件发生在截止时间，[reminderMinutes] 为提前提醒分钟数。
  static Future<CalendarAddResult> addHomeworkEvents(
    List<Homework> items, {
    int reminderMinutes = 120,
  }) async {
    final minutes = reminderMinutes > 0 ? reminderMinutes : 120;
    final events = <Map<String, Object>>[];
    for (final hw in items) {
      final deadline = hw.deadline;
      if (deadline == null) continue;
      events.add({
        'title': '【作业截止】${hw.title}',
        'description':
            '课程：${hw.course}\n'
            '截止时间：${_format(deadline)}\n'
            '提醒：截止前 ${formatReminderLead(minutes)}',
        'startMillis': deadline.millisecondsSinceEpoch,
        'endMillis': deadline
            .add(const Duration(minutes: 15))
            .millisecondsSinceEpoch,
        'remindMinutes': minutes,
      });
    }
    if (events.isEmpty) return const CalendarAddResult();

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'addEvents',
        {'events': events},
      );
      return CalendarAddResult(
        added: _asInt(result?['added']),
        skipped: _asInt(result?['skipped']),
        failed: _asInt(result?['failed']),
      );
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '写入日历失败');
    } on MissingPluginException {
      throw Exception('当前平台不支持日历写入');
    }
  }

  static int _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static String _format(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
