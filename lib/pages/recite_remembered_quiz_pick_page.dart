import 'package:flutter/material.dart';

import '../lesson_repository.dart';
import '../prefs_store.dart';
import 'recite_remembered_quiz_page.dart';

/// 选择若干课（或全部）的已记住单词，进入四选一测验。
class ReciteRememberedQuizPickPage extends StatefulWidget {
  const ReciteRememberedQuizPickPage({super.key});

  @override
  State<ReciteRememberedQuizPickPage> createState() =>
      _ReciteRememberedQuizPickPageState();
}

class _ReciteRememberedQuizPickPageState
    extends State<ReciteRememberedQuizPickPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  Map<String, bool> _rwords = {};
  int _rememberedTotal = 0;

  /// 是否选中「全部已记住」。
  bool _selectAll = true;
  final Set<String> _selectedLessons = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await LessonRepository.instance.load();
    final data = LessonRepository.instance.lessons;
    final rwords = await PrefsStore.instance.loadRemembered();
    final rows = <Map<String, dynamic>>[];
    var totalRemembered = 0;
    for (final lesson in data) {
      final words = lesson['words'] as List? ?? [];
      var n = 0;
      for (final w in words) {
        final wm = w as Map;
        final key = '${wm['lesson']}|${wm['idx']}';
        if (rwords[key] == true) {
          n++;
          totalRemembered++;
        }
      }
      if (n > 0) {
        rows.add({...lesson, 'rwordnum': n});
      }
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _rwords = rwords;
      _rememberedTotal = totalRemembered;
      _loading = false;
      if (_selectAll) {
        _selectedLessons.clear();
      } else if (_selectedLessons.isEmpty && rows.isNotEmpty) {
        _selectedLessons.add(rows.first['lesson'] as String? ?? '');
      }
    });
  }

  int get _selectedCount {
    if (_selectAll) {
      return _rememberedTotal;
    }
    var n = 0;
    for (final g in _rows) {
      final lessonKey = g['lesson'] as String? ?? '';
      if (!_selectedLessons.contains(lessonKey)) {
        continue;
      }
      n += g['rwordnum'] as int? ?? 0;
    }
    return n;
  }

  String get _scopeLabel {
    if (_selectAll) {
      return '全部已记住';
    }
    if (_selectedLessons.isEmpty) {
      return '未选择';
    }
    if (_selectedLessons.length == 1) {
      final key = _selectedLessons.first;
      return '$key（$_selectedCount 词）';
    }
    return '${_selectedLessons.length} 课（$_selectedCount 词）';
  }

  List<Map<String, dynamic>> _collectSelectedWords() {
    final out = <Map<String, dynamic>>[];
    for (final lesson in _rows) {
      final lessonKey = lesson['lesson'] as String? ?? '';
      if (!_selectAll && !_selectedLessons.contains(lessonKey)) {
        continue;
      }
      final words = lesson['words'] as List? ?? [];
      for (final w in words) {
        final wm = Map<String, dynamic>.from(w as Map);
        final key = '${wm['lesson']}|${wm['idx']}';
        if (_rwords[key] == true) {
          out.add(wm);
        }
      }
    }
    return out;
  }

  void _setSelectAll(bool value) {
    setState(() {
      _selectAll = value;
      if (value) {
        _selectedLessons.clear();
      } else if (_selectedLessons.isEmpty && _rows.isNotEmpty) {
        _selectedLessons.add(_rows.first['lesson'] as String? ?? '');
      }
    });
  }

  void _toggleLesson(String lessonKey, bool? checked) {
    setState(() {
      _selectAll = false;
      if (checked == true) {
        _selectedLessons.add(lessonKey);
      } else {
        _selectedLessons.remove(lessonKey);
      }
    });
  }

  void _selectAllLessons() {
    setState(() {
      _selectAll = false;
      _selectedLessons
        ..clear()
        ..addAll(
          _rows.map((g) => g['lesson'] as String? ?? '').where((k) => k.isNotEmpty),
        );
    });
  }

  void _clearLessonSelection() {
    setState(() {
      _selectAll = false;
      _selectedLessons.clear();
    });
  }

  Future<void> _startQuiz() async {
    final list = _collectSelectedWords();
    if (!mounted) return;
    if (list.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedCount == 0
                ? '请先选择至少一课已记住的单词。'
                : '当前范围仅 $_selectedCount 个已记住单词，四选一至少需要 4 个。',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReciteRememberedQuizPage(
          rememberedWords: list,
          scopeLabel: _scopeLabel,
        ),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  static String _lessonSubtitle(Map<String, dynamic> g) {
    return '${g['title'] ?? g['texttitle'] ?? ''}'.replaceAll('\n', ' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择测验范围'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rememberedTotal == 0
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '还没有已记住的单词。\n请先在各课背词中标记「已记住」。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              '测验从所选范围内的已记住单词中出题，选项仅来自同一范围。',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                          CheckboxListTile(
                            value: _selectAll,
                            onChanged: (v) => _setSelectAll(v ?? false),
                            title: const Text('全部已记住'),
                            subtitle: Text('共 $_rememberedTotal 个单词'),
                            secondary: const Icon(Icons.select_all),
                          ),
                          if (!_selectAll) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                children: [
                                  TextButton(
                                    onPressed: _selectAllLessons,
                                    child: const Text('全选各课'),
                                  ),
                                  TextButton(
                                    onPressed: _clearLessonSelection,
                                    child: const Text('清空'),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            ..._rows.map((g) {
                              final lessonKey = g['lesson'] as String? ?? '';
                              final n = g['rwordnum'] as int? ?? 0;
                              return CheckboxListTile(
                                value: _selectedLessons.contains(lessonKey),
                                onChanged: (v) => _toggleLesson(lessonKey, v),
                                title: Text(lessonKey),
                                subtitle: Text(_lessonSubtitle(g)),
                                secondary: Text('$n'),
                                controlAffinity: ListTileControlAffinity.leading,
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '已选 $_selectedCount 个单词',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: _selectedCount >= 4 ? _startQuiz : null,
                              child: Text(
                                _selectedCount >= 4
                                    ? '开始测验'
                                    : '至少需 4 个已记住单词',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
