/// 把提前提醒的分钟数格式化为中文描述，例如：
/// 120 → "2 小时"，1500 → "1 天 1 小时"，45 → "45 分钟"。
String formatReminderLead(int totalMinutes) {
  if (totalMinutes <= 0) return '不提醒';
  final days = totalMinutes ~/ 1440;
  final hours = (totalMinutes % 1440) ~/ 60;
  final minutes = totalMinutes % 60;

  final parts = <String>[];
  if (days > 0) parts.add('$days 天');
  if (hours > 0) parts.add('$hours 小时');
  if (minutes > 0) parts.add('$minutes 分钟');
  return parts.join(' ');
}
