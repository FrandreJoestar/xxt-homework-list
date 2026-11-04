import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本机持久化：学习通凭据与会话 Cookie。
class SessionStore {
  static const _phoneKey = 'chaoxing_phone';
  static const _passwordKey = 'chaoxing_password';
  static const _cookiesKey = 'chaoxing_cookies';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String?> readPhone() async => (await _prefs).getString(_phoneKey);
  Future<String?> readPassword() async =>
      (await _prefs).getString(_passwordKey);

  Future<void> saveCredentials(String phone, String password) async {
    final prefs = await _prefs;
    await prefs.setString(_phoneKey, phone);
    await prefs.setString(_passwordKey, password);
  }

  Future<Map<String, String>> readCookies() async {
    final raw = (await _prefs).getString(_cookiesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return {};
  }

  Future<void> saveCookies(Map<String, String> cookies) async {
    final prefs = await _prefs;
    await prefs.setString(_cookiesKey, jsonEncode(cookies));
  }

  Future<bool> hasCredentials() async {
    final prefs = await _prefs;
    return (prefs.getString(_phoneKey) ?? '').isNotEmpty &&
        (prefs.getString(_passwordKey) ?? '').isNotEmpty;
  }

  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_phoneKey);
    await prefs.remove(_passwordKey);
    await prefs.remove(_cookiesKey);
  }
}
