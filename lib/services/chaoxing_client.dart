import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show BytesBuilder;

import 'package:encrypt/encrypt.dart';

import '../models/homework.dart';
import 'session_store.dart';

class ChaoxingException implements Exception {
  final String message;
  final bool needLogin;

  const ChaoxingException(this.message, {this.needLogin = false});

  @override
  String toString() => message;
}

class _HttpResult {
  final Uri uri;
  final int statusCode;
  final String body;

  const _HttpResult(this.uri, this.statusCode, this.body);
}

/// 学习通（超星）只读客户端：登录 + 课程 / 作业 / 截止时间抓取。
///
/// 协议参考 xuexitong-cli-main/xuexitong_mcp/client.py：
///   - 登录：passport2.chaoxing.com/fanyalogin（账号密码 AES-128-CBC 加密）
///   - 课程：mooc2-ans.chaoxing.com/mooc2-ans/visit/courselistdata
///   - 作业：课程中间页取 workEnc/openc/enc → mooc1.chaoxing.com/mooc2/work/list
///   - 截止时间：逐份请求作业详情页，解析“作答时间 A 至 B”中的 B
class ChaoxingClient {
  ChaoxingClient([SessionStore? store]) : _store = store ?? SessionStore();

  final SessionStore _store;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  final Map<String, String> _cookies = {};

  String? _phone;
  String? _password;
  bool _verified = false;
  bool _sessionLoaded = false;
  Future<void>? _ensuring;

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36';
  static const String _aesSecret = 'u2oh6Vu^HWe4_AES';

  static const String _baseUrl = 'https://i.chaoxing.com/base';
  static const String _loginUrl = 'https://passport2.chaoxing.com/fanyalogin';
  static const String _courseListUrl =
      'https://mooc2-ans.chaoxing.com/mooc2-ans/visit/courselistdata';
  static const String _courseMiddleUrl =
      'https://mooc1.chaoxing.com/visit/stucoursemiddle';
  static const String _workListUrl =
      'https://mooc1.chaoxing.com/mooc2/work/list';

  static const Duration _timeout = Duration(seconds: 30);

  Future<void> loadSession() async {
    if (_sessionLoaded) return;
    _sessionLoaded = true;
    _cookies.addAll(await _store.readCookies());
    _phone = await _store.readPhone();
    _password = await _store.readPassword();
  }

  void dispose() {
    _http.close(force: true);
  }

  // ------------------------------------------------------------ 登录

  /// 账号密码登录（成功后持久化 Cookie 与凭据）。
  Future<void> login(String phone, String password) async {
    final p = phone.trim();
    if (p.isEmpty || password.isEmpty) {
      throw const ChaoxingException('请输入手机号与密码');
    }
    _phone = p;
    _password = password;

    final result = await _send(
      'POST',
      Uri.parse(_loginUrl),
      form: {
        'fid': '-1',
        'uname': _aesEncrypt(p),
        'password': _aesEncrypt(password),
        'refer': 'https%3A%2F%2Fi.chaoxing.com',
        't': 'true',
        'forbidotherlogin': '0',
        'validate': '',
        'doubleFactorLogin': '0',
        'independentId': '0',
      },
    ).timeout(_timeout);

    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(result.body.replaceFirst('\uFEFF', '').trim());
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {}

    if (json == null || json['status'] != true) {
      final msg = json?['msg2']?.toString();
      throw ChaoxingException(
        (msg == null || msg.isEmpty) ? '登录失败，请检查手机号与密码（或稍后重试）' : msg,
        needLogin: true,
      );
    }

    _verified = true;
    await _store.saveCredentials(p, password);
    await _store.saveCookies(_cookies);
  }

  /// 已登录则直接返回；Cookie 失效时用已保存凭据自动重登。
  Future<void> ensureLogin({bool force = false}) async {
    if (!force && _verified) return;
    final pending = _ensuring;
    if (pending != null) {
      await pending;
      if (!force && _verified) return;
    }
    final future = _doEnsureLogin(force: force);
    _ensuring = future;
    try {
      await future;
    } finally {
      if (identical(_ensuring, future)) _ensuring = null;
    }
  }

  Future<void> _doEnsureLogin({required bool force}) async {
    await loadSession();
    if (!force && _verified) return;
    _verified = false;

    if (_cookies.isNotEmpty) {
      try {
        final probe = await _get(Uri.parse(_baseUrl));
        if (!_isLoginPage(probe)) {
          _verified = true;
          return;
        }
      } catch (_) {
        // 网络异常时继续尝试用凭据登录
      }
    }

    final phone = _phone;
    final password = _password;
    if (phone == null || password == null || phone.isEmpty) {
      throw const ChaoxingException('尚未登录学习通账号', needLogin: true);
    }
    await login(phone, password);
  }

  bool _isLoginPage(_HttpResult r) {
    final url = r.uri.toString();
    return url.contains('passport2.chaoxing.com/login') ||
        r.body.contains('用户登录');
  }

  // ------------------------------------------------------------ 数据接口

  /// 我学的全部课程。
  Future<List<Course>> fetchCourses() async {
    final base = await _getAuthed(Uri.parse(_baseUrl));
    final fid =
        RegExp(r'"fid"\s*:\s*"?(\d+)"?').firstMatch(base.body)?.group(1) ??
        RegExp(r"var fid = '(\d+)'").firstMatch(base.body)?.group(1) ??
        '427';
    final uri = Uri.parse(_courseListUrl).replace(
      queryParameters: {
        'courseType': '1',
        'courseFid': fid,
        'courseTeacherid': '0',
        'courseOrderBy': '0',
      },
    );
    final result = await _getAuthed(uri);
    return _parseCourses(result.body);
  }

  /// 单门课的作业列表（尚未补截止时间）。
  Future<List<Homework>> fetchHomeworkList(Course course) async {
    final page = await _getAuthed(
      Uri.parse(_courseMiddleUrl).replace(
        queryParameters: {
          'courseid': course.courseid,
          'clazzid': course.clazzid,
          'cpi': course.cpi,
          'ismooc2': '1',
          'v': '2',
        },
      ),
    );
    final workEnc = _hiddenValue(page.body, 'workEnc');
    final openc = _hiddenValue(page.body, 'openc');
    final pageEnc = _hiddenValue(page.body, 'enc');
    if (workEnc.isEmpty) {
      throw ChaoxingException('课程「${course.name}」未开放作业功能');
    }

    final uri = Uri.parse(_workListUrl).replace(
      queryParameters: {
        'courseId': course.courseid,
        'classId': course.clazzid,
        'cpi': course.cpi,
        'ut': 's',
        'openc': openc,
        'enc': workEnc,
        't': DateTime.now().millisecondsSinceEpoch.toString(),
        'stuenc': pageEnc,
        'isdisplaytable': '2',
      },
    );
    final result = await _getAuthed(uri);
    if (result.body.contains('没有此页面访问权限')) {
      throw ChaoxingException('课程「${course.name}」作业签名校验失败，请稍后重试');
    }
    return _parseHomeworkList(result.body, course.name);
  }

  /// 从作业详情页解析截止时间；解析不到返回 null。
  Future<DateTime?> fetchDeadline(String url) async {
    if (url.isEmpty) return null;
    final result = await _getAuthed(Uri.parse(url));
    return _parseDeadline(result.body, DateTime.now());
  }

  /// 扫描所有课程的作业（含已提交 / 已截止），并补全截止时间。
  Future<HomeworkFetchResult> fetchAllHomework({
    void Function(int done, int total)? onProgress,
  }) async {
    final courses = await fetchCourses();
    final failed = <String>[];
    final items = <Homework>[];
    var done = 0;
    onProgress?.call(0, courses.length);

    await _mapLimit<Course>(courses, 4, (course) async {
      try {
        final list = await fetchHomeworkList(course);
        final withDeadline = await _mapLimitResult<Homework, Homework>(
          list,
          4,
          (hw) async {
            if (hw.url.isEmpty) return hw;
            try {
              final deadline = await fetchDeadline(hw.url);
              return hw.copyWithDeadline(deadline);
            } catch (_) {
              return hw;
            }
          },
        );
        items.addAll(withDeadline);
      } catch (_) {
        failed.add(course.name);
      }
      done++;
      onProgress?.call(done, courses.length);
    });

    return HomeworkFetchResult(
      items: items,
      failedCourses: failed,
      totalCourses: courses.length,
    );
  }

  // ------------------------------------------------------------ HTTP

  Future<_HttpResult> _get(Uri uri) async {
    return _send('GET', uri).timeout(_timeout);
  }

  Future<_HttpResult> _getAuthed(Uri uri) async {
    await ensureLogin();
    var result = await _get(uri);
    if (_isLoginPage(result)) {
      await ensureLogin(force: true);
      result = await _get(uri);
    }
    return result;
  }

  Future<_HttpResult> _send(
    String method,
    Uri uri, {
    Map<String, String>? form,
  }) async {
    var current = uri;
    for (var hop = 0; hop < 6; hop++) {
      final request = await _http.openUrl(method, current);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, _ua);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
      );
      request.headers.set(HttpHeaders.acceptLanguageHeader, 'zh-CN,zh;q=0.9');
      if (_cookies.isNotEmpty) {
        request.headers.set(
          HttpHeaders.cookieHeader,
          _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
        );
      }
      if (form != null) {
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request.write(_encodeForm(form));
      }

      final response = await request.close().timeout(_timeout);
      _captureCookies(response);

      final location = response.headers.value(HttpHeaders.locationHeader);
      if (response.isRedirect && location != null && hop < 5) {
        await response.drain<void>();
        current = current.resolve(location);
        continue;
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return _HttpResult(
        current,
        response.statusCode,
        _decodeBody(response, builder.takeBytes()),
      );
    }
    throw const ChaoxingException('请求重定向次数过多');
  }

  void _captureCookies(HttpClientResponse response) {
    final values = response.headers[HttpHeaders.setCookieHeader];
    if (values == null) return;
    for (final raw in values) {
      final pair = raw.split(';').first;
      final index = pair.indexOf('=');
      if (index <= 0) continue;
      final name = pair.substring(0, index).trim();
      final value = pair.substring(index + 1).trim();
      if (name.isNotEmpty) _cookies[name] = value;
    }
  }

  String _decodeBody(HttpClientResponse response, List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  String _encodeForm(Map<String, String> form) => form.entries
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
      )
      .join('&');

  String _aesEncrypt(String text) {
    final key = Key.fromUtf8(_aesSecret);
    final iv = IV.fromUtf8(_aesSecret);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
    return encrypter.encrypt(text, iv: iv).base64;
  }

  // ------------------------------------------------------------ 解析

  List<Course> _parseCourses(String html) {
    final result = <Course>[];
    final seen = <String>{};
    final reg = RegExp(
      r'stucoursemiddle\?courseid=(\d+)&clazzid=(\d+)&cpi=(\d+)',
    );
    for (final match in reg.allMatches(html)) {
      final courseid = match.group(1)!;
      final clazzid = match.group(2)!;
      final cpi = match.group(3)!;
      final key = '$courseid/$clazzid/$cpi';
      if (!seen.add(key)) continue;

      final start = match.end;
      final end = min(start + 2500, html.length);
      final segment = html.substring(start, end);
      final nameMatch = RegExp(
        r'course-name[^>]*title="([^"]+)"',
      ).firstMatch(segment);
      String teacher = '';
      final teacherMatch = RegExp(
        r'<p class="line2 color3"[^>]*title="([^"]+)"',
      ).firstMatch(segment);
      if (teacherMatch != null) {
        teacher = _htmlUnescape(teacherMatch.group(1)!).trim();
      }

      result.add(
        Course(
          name: nameMatch == null ? '未知课程' : _htmlUnescape(nameMatch.group(1)!),
          teacher: teacher,
          courseid: courseid,
          clazzid: clazzid,
          cpi: cpi,
        ),
      );
    }
    return result;
  }

  List<Homework> _parseHomeworkList(String html, String courseName) {
    final result = <Homework>[];
    final reg = RegExp(
      r'<li onclick="goTask\(this\);" data="([^"]+)"[\s\S]*?'
      r'<p class="overHidden2 fl">([^<]+)</p>[\s\S]*?'
      r'<p class="status fl">([^<]*)</p>',
    );
    for (final match in reg.allMatches(html)) {
      final rawUrl = _htmlUnescape(match.group(1)!).trim();
      final title = _htmlUnescape(match.group(2)!).trim();
      final status = _htmlUnescape(match.group(3)!).trim();
      result.add(
        Homework(
          course: courseName,
          title: title.isEmpty ? '未命名作业' : title,
          status: status,
          url: _decodeUrl(rawUrl),
        ),
      );
    }
    return result;
  }

  String _decodeUrl(String raw) {
    if (!raw.startsWith('http')) return '';
    try {
      return Uri.decodeFull(raw);
    } catch (_) {
      return raw;
    }
  }

  String _hiddenValue(String html, String id) {
    final first = RegExp('id="$id"[^>]*value="([^"]*)"').firstMatch(html);
    if (first != null) return first.group(1)!;
    final second = RegExp('value="([^"]*)"[^>]*id="$id"').firstMatch(html);
    return second?.group(1) ?? '';
  }

  DateTime? _parseDeadline(String html, DateTime now) {
    final text = _stripTags(html);

    // 作答时间: 06-21 18:51 至 07-01 18:51（年份可能缺省，也可能带 2026-）
    final span = RegExp(
      r'作答时间[:：]\s*(?:(\d{4})-)?(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})'
      r'\s*至\s*(?:(\d{4})-)?(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})',
    ).firstMatch(text);
    if (span != null) {
      return _buildDate(
        year: span.group(6),
        month: span.group(7),
        day: span.group(8),
        hour: span.group(9),
        minute: span.group(10),
        today: now,
      );
    }

    // 兜底：详情页单独标注“截止时间”
    final single = RegExp(
      r'截止时间[:：]\s*(?:(\d{4})-)?(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})',
    ).firstMatch(text);
    if (single != null) {
      return _buildDate(
        year: single.group(1),
        month: single.group(2),
        day: single.group(3),
        hour: single.group(4),
        minute: single.group(5),
        today: now,
      );
    }

    // 再兜底：页面上任意“A 至 B”时间段，取 B
    final loose = RegExp(
      r'(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})\s*至\s*'
      r'(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})',
    ).firstMatch(text);
    if (loose != null) {
      return _buildDate(
        year: null,
        month: loose.group(5),
        day: loose.group(6),
        hour: loose.group(7),
        minute: loose.group(8),
        today: now,
      );
    }
    return null;
  }

  DateTime? _buildDate({
    required String? year,
    required String? month,
    required String? day,
    required String? hour,
    required String? minute,
    required DateTime today,
  }) {
    if (month == null || day == null || hour == null || minute == null) {
      return null;
    }
    final mo = int.tryParse(month);
    final d = int.tryParse(day);
    final h = int.tryParse(hour);
    final mi = int.tryParse(minute);
    if (mo == null || d == null || h == null || mi == null) return null;

    if (year != null) {
      final y = int.tryParse(year);
      if (y == null) return null;
      final candidate = DateTime(y, mo, d, h, mi);
      if (candidate.month != mo || candidate.day != d) return null;
      return candidate;
    }
    return _nearestDateTime(mo, d, h, mi, today);
  }

  /// 详情页日期没有年份时，取与今天最接近的年份（跨年作业才不会排错）。
  DateTime? _nearestDateTime(
    int month,
    int day,
    int hour,
    int minute,
    DateTime today,
  ) {
    DateTime? best;
    for (final year in [today.year - 1, today.year, today.year + 1]) {
      final candidate = DateTime(year, month, day, hour, minute);
      if (candidate.month != month || candidate.day != day) continue;
      if (best == null ||
          candidate.difference(today).inDays.abs() <
              best.difference(today).inDays.abs()) {
        best = candidate;
      }
    }
    return best;
  }

  String _stripTags(String html) {
    var text = html.replaceAll(
      RegExp(r'<script[\s\S]*?</script>|<style[\s\S]*?</style>'),
      ' ',
    );
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = _htmlUnescape(text);
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _htmlUnescape(String text) {
    var out = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    return out;
  }

  // ------------------------------------------------------------ 并发工具

  Future<void> _mapLimit<T>(
    List<T> input,
    int limit,
    Future<void> Function(T item) action,
  ) async {
    if (input.isEmpty) return;
    var index = 0;
    Future<void> worker() async {
      while (true) {
        final current = index;
        index++;
        if (current >= input.length) return;
        await action(input[current]);
      }
    }

    await Future.wait(List.generate(min(limit, input.length), (_) => worker()));
  }

  Future<List<R>> _mapLimitResult<T, R>(
    List<T> input,
    int limit,
    Future<R> Function(T item) action,
  ) async {
    if (input.isEmpty) return <R>[];
    final output = List<R?>.filled(input.length, null);
    var index = 0;
    Future<void> worker() async {
      while (true) {
        final current = index;
        index++;
        if (current >= input.length) return;
        output[current] = await action(input[current]);
      }
    }

    await Future.wait(List.generate(min(limit, input.length), (_) => worker()));
    return output.cast<R>();
  }
}
