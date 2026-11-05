import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xuexitong_homework/models/homework.dart';
import 'package:xuexitong_homework/services/homework_cache.dart';
import 'package:xuexitong_homework/utils/reminder_text.dart';
import 'package:xuexitong_homework/widgets/reminder_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Homework homework(String status, DateTime? deadline) => Homework(
    course: '测试课程',
    title: '测试作业',
    status: status,
    deadline: deadline,
  );

  test('已交分类不包含已截止的作业', () {
    final now = DateTime.now();
    final submitted = homework('已提交', now.add(const Duration(days: 1)));
    final submittedExpired = homework(
      '已提交',
      now.subtract(const Duration(days: 1)),
    );

    expect(submitted.matches(HomeworkFilter.submitted), isTrue);
    expect(submitted.matches(HomeworkFilter.expired), isFalse);

    expect(submittedExpired.matches(HomeworkFilter.submitted), isFalse);
    expect(submittedExpired.matches(HomeworkFilter.expired), isTrue);
    expect(submittedExpired.matches(HomeworkFilter.all), isTrue);
  });

  test('未交分类只保留未截止且未提交的作业', () {
    final now = DateTime.now();
    final pending = homework('待提交', now.add(const Duration(days: 2)));
    final pendingExpired = homework(
      '待提交',
      now.subtract(const Duration(days: 2)),
    );
    final done = homework('已完成', now.add(const Duration(days: 2)));

    expect(pending.matches(HomeworkFilter.pending), isTrue);
    expect(pendingExpired.matches(HomeworkFilter.pending), isFalse);
    expect(done.matches(HomeworkFilter.pending), isFalse);
  });

  test('状态文案为已截止时即使没有截止时间也归入已截止', () {
    final item = homework('已截止', null);
    expect(item.isExpired, isTrue);
    expect(item.matches(HomeworkFilter.expired), isTrue);
    expect(item.matches(HomeworkFilter.submitted), isFalse);
  });

  test('作业缓存可读写，并标记为当天数据', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = HomeworkCache();
    final deadline = DateTime.now().add(const Duration(hours: 3));

    await cache.save(
      HomeworkFetchResult(
        items: [
          Homework(
            course: '高等数学',
            title: '第三章习题',
            status: '待提交',
            url: 'https://example.com/task/1',
            deadline: deadline,
          ),
        ],
        failedCourses: const ['未开放作业的课程'],
        totalCourses: 1,
      ),
    );

    final entry = await cache.read();
    expect(entry, isNotNull);
    expect(entry!.isFromToday, isTrue);
    expect(entry.items.single.title, '第三章习题');
    expect(entry.items.single.course, '高等数学');
    expect(
      entry.items.single.deadline?.millisecondsSinceEpoch,
      deadline.millisecondsSinceEpoch,
    );
    expect(entry.failedCourses, ['未开放作业的课程']);

    await cache.clear();
    expect(await cache.read(), isNull);
  });

  test('昨天的缓存不会被判定为当天数据', () {
    final entry = HomeworkCacheEntry(
      items: const [],
      failedCourses: const [],
      savedAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(entry.isFromToday, isFalse);
  });

  test('提前提醒时间文案格式化', () {
    expect(formatReminderLead(0), '不提醒');
    expect(formatReminderLead(45), '45 分钟');
    expect(formatReminderLead(120), '2 小时');
    expect(formatReminderLead(1500), '1 天 1 小时');
  });

  testWidgets('提前提醒选择器默认返回 2 小时', (tester) async {
    Duration? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await showReminderPicker(context);
                },
                child: const Text('打开选择器'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开选择器'));
    await tester.pumpAndSettle();
    expect(find.text('提前提醒'), findsOneWidget);
    expect(find.text('将在截止前 2 小时提醒'), findsOneWidget);

    await tester.tap(find.text('确定导入'));
    await tester.pumpAndSettle();
    expect(picked, const Duration(hours: 2));
  });
}
