import 'dart:convert';
import 'dart:ffi';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 一条可用的更新信息。
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.build,
    required this.currentVersion,
    required this.downloadUrl,
    required this.proxy,
  });

  final String version;
  final int build;
  final String currentVersion;

  /// 已拼接加速前缀的安装包下载地址。
  final String downloadUrl;

  /// 命中的加速前缀，空字符串代表直连 GitHub。
  final String proxy;
}

/// 应用更新检查：读取 GitHub Release 的 latest/version.json。
///
/// 依次尝试直连与常用加速代理，任一源成功即可；全部失败时静默返回 null。
class UpdateService {
  UpdateService._();

  static const String repository = 'FrandreJoestar/xxt-homework-list';

  static const String _versionUrl =
      'https://github.com/$repository/releases/latest/download/version.json';

  /// 直连 + 常用 GitHub 加速代理（按顺序尝试）。
  static const List<String> _proxies = [
    '',
    'https://gh-proxy.com/',
    'https://ghproxy.net/',
    'https://ghfast.top/',
  ];

  static const Duration _timeout = Duration(seconds: 6);

  /// 启动时调用。有新版本时返回更新信息，已是最新或检查失败返回 null。
  static Future<AppUpdate?> checkForUpdate() async {
    final PackageInfo info;
    try {
      info = await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;

    for (final proxy in _proxies) {
      final data = await _fetchVersion(proxy);
      if (data == null) continue;

      final rawVersion = (data['version'] as String?)?.trim() ?? '';
      final version = rawVersion.startsWith('v')
          ? rawVersion.substring(1)
          : rawVersion;
      if (version.isEmpty) continue;

      final build = (data['build'] as num?)?.toInt() ?? 0;
      final apkUrl = _selectApkUrl(data);
      if (apkUrl == null) continue;

      final comparison = _compareVersion(version, info.version);
      // 拿到第一个有效结果就足够：版本不高于当前则无需继续尝试其他代理。
      if (comparison < 0) return null;
      if (comparison == 0 && build <= currentBuild) return null;

      return AppUpdate(
        version: version,
        build: build,
        currentVersion: info.version,
        downloadUrl: proxy.isEmpty ? apkUrl : '$proxy$apkUrl',
        proxy: proxy,
      );
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _fetchVersion(String proxy) async {
    try {
      final response = await http
          .get(Uri.parse('$proxy$_versionUrl'))
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// 优先按当前设备 ABI 选择分包，找不到时回退到通用包 apkUrl。
  static String? _selectApkUrl(Map<String, dynamic> data) {
    final urls = data['apkUrls'];
    final abi = _currentAbiKey();
    if (urls is Map && abi != null) {
      final candidate = urls[abi];
      if (candidate is String && candidate.trim().startsWith('http')) {
        return candidate.trim();
      }
    }
    final fallback = (data['apkUrl'] as String?)?.trim() ?? '';
    return fallback.startsWith('http') ? fallback : null;
  }

  static String? _currentAbiKey() {
    try {
      final abi = Abi.current();
      if (abi == Abi.androidArm64) return 'arm64-v8a';
      if (abi == Abi.androidArm) return 'armeabi-v7a';
      if (abi == Abi.androidIA32) return 'x86';
      if (abi == Abi.androidX64) return 'x86_64';
      return null;
    } catch (_) {
      return null;
    }
  }

  static int _compareVersion(String a, String b) {
    final left = a.split('.');
    final right = b.split('.');
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final x = i < left.length ? int.tryParse(left[i]) ?? 0 : 0;
      final y = i < right.length ? int.tryParse(right[i]) ?? 0 : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// 用外部浏览器打开下载地址；返回是否成功。
  static Future<bool> openDownload(AppUpdate update) async {
    try {
      return await launchUrl(
        Uri.parse(update.downloadUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
