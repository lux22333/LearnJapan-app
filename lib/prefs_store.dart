import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 对应 Ionic 中 `localStorage` 的 `rwords`：键为 `lesson|idx`。
class PrefsStore {
  PrefsStore._();

  static final PrefsStore instance = PrefsStore._();

  static const _keyRwords = 'rwords';

  Future<Map<String, bool>> loadRemembered() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_keyRwords);
    if (s == null || s.isEmpty) return {};
    final decoded = jsonDecode(s);
    if (decoded is! Map) return {};
    return decoded.map((k, v) => MapEntry(k.toString(), v == true));
  }

  Future<void> saveRemembered(Map<String, bool> rwords) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyRwords, jsonEncode(rwords));
  }

  Future<void> importRememberedJson(String jsonStr) async {
    final decoded = jsonDecode(jsonStr);
    if (decoded is Map) {
      final m = decoded.map((k, v) => MapEntry(k.toString(), v == true));
      await saveRemembered(m);
    } else {
      throw FormatException('无效的学习记录');
    }
  }

  Future<String?> exportRememberedJson() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyRwords);
  }
}
