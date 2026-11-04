import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/homework.dart';

class HomeworkCacheEntry {
  final List<Homework> items;
  final List<String> failedCourses;
  final DateTime savedAt;

  const HomeworkCacheEntry({
    required this.items,
    required this.failedCourses,
    required this.savedAt,
  });

  /// 是否为当天缓存（当天再次打开应用可直接使用，不再请求网络）。
  bool get isFromToday {
    final now = DateTime.now();
    return savedAt.year == now.year &&
        savedAt.month == now.month &&
        savedAt.day == now.day;
  }
}

/// 作业列表本地缓存：每天自动拉取一次，其余时间直接读取本机数据。
class HomeworkCache {
  static const String _key = 'homework_cache_v1';

  Future<HomeworkCacheEntry?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;

      final map = jsonDecode(raw);
      if (map is! Map) return null;

      final savedAt = DateTime.tryParse('${map['savedAt'] ?? ''}');
      if (savedAt == null) return null;

      final items = <Homework>[];
      for (final rawItem in (map['items'] as List? ?? const [])) {
        if (rawItem is! Map) continue;
        final deadlineMillis = rawItem['deadline'];
        items.add(
          Homework(
            course: '${rawItem['course'] ?? ''}',
            title: '${rawItem['title'] ?? ''}',
            status: '${rawItem['status'] ?? ''}',
            url: '${rawItem['url'] ?? ''}',
            deadline: deadlineMillis is num
                ? DateTime.fromMillisecondsSinceEpoch(deadlineMillis.toInt())
                : null,
            deadlineText: '${rawItem['deadlineText'] ?? ''}',
          ),
        );
      }

      final failedCourses = (map['failedCourses'] as List? ?? const [])
          .map((e) => e.toString())
          .toList();

      return HomeworkCacheEntry(
        items: items,
        failedCourses: failedCourses,
        savedAt: savedAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(HomeworkFetchResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, Object?>{
      'savedAt': DateTime.now().toIso8601String(),
      'failedCourses': result.failedCourses,
      'items': [
        for (final homework in result.items)
          {
            'course': homework.course,
            'title': homework.title,
            'status': homework.status,
            'url': homework.url,
            'deadline': homework.deadline?.millisecondsSinceEpoch,
            'deadlineText': homework.deadlineText,
          },
      ],
    };
    await prefs.setString(_key, jsonEncode(data));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
