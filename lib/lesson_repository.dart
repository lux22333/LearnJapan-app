import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 对应 Ionic `items.ts` 中的 `formatLessons` / `queryLessons`。
class LessonRepository {
  LessonRepository._();

  static final LessonRepository instance = LessonRepository._();

  Map<String, dynamic>? _origin;
  List<Map<String, dynamic>>? _lessons;

  Map<String, dynamic>? get origin => _origin;

  Future<void> load() async {
    if (_lessons != null) return;
    final raw = await rootBundle.loadString('assets/data/lessons_bundle.json');
    _origin = jsonDecode(raw) as Map<String, dynamic>;
    _lessons = _formatLessons(_origin!);
  }

  List<Map<String, dynamic>> get lessons {
    assert(_lessons != null, 'Call load() first');
    return _lessons!;
  }

  static String _pad(int num, int size) => num.toString().padLeft(size, '0');

  static Map<String, dynamic> _trimAll(Map<String, dynamic> arr) {
    final o = Map<String, dynamic>.from(arr);
    o.updateAll((k, v) {
      if (v is String) return v.trim();
      return v;
    });
    return o;
  }

  static String _cleanLine(String line) =>
      line.replaceFirst(RegExp(r'^(> )?\* '), '');

  static List<String> _splitText(String? text) {
    if (text == null || text.isEmpty) return [];
    return text
        .split('\n')
        .map(_cleanLine)
        .where((o) => o.isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> _formatLessons(Map<String, dynamic> odata) {
    final level1 = Map<String, dynamic>.from(odata['level1'] as Map);
    final level2 = Map<String, dynamic>.from(odata['level2'] as Map);
    final ldata = <String, dynamic>{...level1, ...level2};

    final grammar = (odata['grammar'] as List)
        .map((e) => _trimAll(Map<String, dynamic>.from(e as Map)))
        .toList();
    final words = (odata['words'] as List)
        .map((e) => _trimAll(Map<String, dynamic>.from(e as Map)))
        .toList();

    final pdata = <Map<String, dynamic>>[];

    final keys = ldata.keys.toList()
      ..sort((a, b) {
        final pa = a[0];
        final pb = b[0];
        if (pa != pb) return pa.compareTo(pb);
        final na = int.parse(a.substring(1));
        final nb = int.parse(b.substring(1));
        return na.compareTo(nb);
      });

    for (final key in keys) {
      final obj = Map<String, dynamic>.from(ldata[key] as Map);
      final prefix = key[0];
      final num = int.parse(key.substring(1));
      final lkey = '${prefix == 'l' ? '0' : 'm'}${_pad(num, 2)}';
      obj['key'] = lkey;
      obj['okey'] = key;
      obj['lesson'] = '${prefix == 'l' ? '初级' : '中级'}第$num課';

      if (prefix == 'l') {
        final basic4 = obj['basic4'] as String? ?? '';
        final first = basic4.split('\n').first;
        obj['title'] = first.replaceFirst('> * ', '').replaceFirst('。', '');
        for (final entity in [
          'basic4',
          'basicc',
          'context',
          'basic4t',
          'basicct',
          'contextt',
        ]) {
          obj[entity] = _splitText(obj[entity] as String?);
        }
      } else {
        for (final entity in ['conversation', 'text']) {
          obj[entity] = _splitText(obj[entity] as String?);
        }
      }

      obj['grammar'] = grammar.where((g) => g['lesson'] == lkey).toList();
      obj['words'] = words.where((w) {
        final wl = w['lesson'] as String? ?? '';
        return wl.startsWith(lkey);
      }).toList();

      pdata.add(obj);
    }
    return pdata;
  }

  /// 搜索：与 `items.ts` queryLessons(search) 行为一致。
  SearchResult search(String query) {
    final q = query.trim();
    if (q.isEmpty || _origin == null) {
      return SearchResult(words: const [], grammar: const []);
    }
    final words = (_origin!['words'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((w) => _inAnyProp(w, ['kana', 'kanji', 'desc'], q))
        .toList();
    final grammar = (_origin!['grammar'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where(
          (g) => _inAnyProp(
            g,
            ['expression', 'explanation', 'shortexplain'],
            q,
          ),
        )
        .toList();
    return SearchResult(words: words, grammar: grammar);
  }

  static bool _inAnyProp(Map<String, dynamic> obj, List<String> props, String testStr) {
    final t = testStr.toLowerCase();
    for (final p in props) {
      final v = obj[p];
      if (v != null && v.toString().toLowerCase().contains(t)) {
        return true;
      }
    }
    return false;
  }
}

class SearchResult {
  SearchResult({required this.words, required this.grammar});

  final List<Map<String, dynamic>> words;
  final List<Map<String, dynamic>> grammar;
}
