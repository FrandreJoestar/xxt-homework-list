/// 学习通作业数据模型与分类规则。
///
/// 分类口径（与需求一致）：
///   - 未交：尚未提交，且未过截止时间
///   - 已交：已提交，且未过截止时间（已截止的作业不再出现在这里）
///   - 已截止：过了截止时间（不论是否提交）
///   - 全部：以上全部
class Course {
  final String name;
  final String teacher;
  final String courseid;
  final String clazzid;
  final String cpi;

  const Course({
    required this.name,
    required this.courseid,
    required this.clazzid,
    required this.cpi,
    this.teacher = '',
  });
}

class Homework {
  final String course;
  final String title;
  final String status;
  final String url;
  final DateTime? deadline;
  final String deadlineText;

  const Homework({
    required this.course,
    required this.title,
    this.status = '',
    this.url = '',
    this.deadline,
    this.deadlineText = '',
  });

  static const List<String> _doneMarks = [
    '已完成',
    '已提交',
    '待批阅',
    '已批阅',
    '已批改',
    '已交',
  ];

  /// 是否已提交/已交（学习通的“待批阅/已批阅”都代表交过了）。
  bool get isSubmitted {
    final s = status.trim();
    return _doneMarks.any(s.contains);
  }

  /// 是否已过截止时间。状态里写明“已截止/已过期”时也算。
  bool get isExpired {
    if (status.contains('已截止') || status.contains('已过期')) return true;
    final d = deadline;
    return d != null && d.isBefore(DateTime.now());
  }

  bool get isPending => !isSubmitted && !isExpired;

  /// 列表内唯一标识（刷新前后同一份作业保持一致）。
  String get id => url.isNotEmpty
      ? url
      : '$course|$title|$status|${deadline?.millisecondsSinceEpoch ?? ''}';

  String get displayStatus {
    final s = status.trim();
    if (s.isEmpty) return isExpired ? '已截止' : '未提交';
    return s;
  }

  bool matches(HomeworkFilter filter) {
    switch (filter) {
      case HomeworkFilter.all:
        return true;
      case HomeworkFilter.pending:
        return isPending;
      case HomeworkFilter.submitted:
        return isSubmitted && !isExpired;
      case HomeworkFilter.expired:
        return isExpired;
    }
  }

  Homework copyWithDeadline(DateTime? value, [String text = '']) {
    return Homework(
      course: course,
      title: title,
      status: status,
      url: url,
      deadline: value ?? deadline,
      deadlineText: text.isEmpty ? deadlineText : text,
    );
  }
}

enum HomeworkFilter {
  all('全部'),
  pending('未交'),
  submitted('已交'),
  expired('已截止');

  final String label;
  const HomeworkFilter(this.label);
}

/// 按当前分类排序：未过期的按截止时间由近到远；过期的按截止时间由近到远
/// 排在后面；“全部”里已截止的沉底。没有截止时间的排最后。
List<Homework> sortedByFilter(List<Homework> source, HomeworkFilter filter) {
  final list = source.where((h) => h.matches(filter)).toList();
  list.sort((a, b) {
    final ad = a.deadline;
    final bd = b.deadline;
    if (filter == HomeworkFilter.all && a.isExpired != b.isExpired) {
      return a.isExpired ? 1 : -1;
    }
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    if (filter == HomeworkFilter.expired ||
        (filter == HomeworkFilter.all && a.isExpired)) {
      return bd.compareTo(ad);
    }
    return ad.compareTo(bd);
  });
  return list;
}

class HomeworkFetchResult {
  final List<Homework> items;
  final List<String> failedCourses;
  final int totalCourses;

  const HomeworkFetchResult({
    required this.items,
    required this.failedCourses,
    required this.totalCourses,
  });
}
