import 'package:flutter/material.dart';

import '../lesson_repository.dart';
import '../prefs_store.dart';
import 'recite_page.dart';
import 'recite_remembered_quiz_page.dart';

class ReciteListPage extends StatefulWidget {
  const ReciteListPage({super.key});

  @override
  State<ReciteListPage> createState() => _ReciteListPageState();
}

class _ReciteListPageState extends State<ReciteListPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  /// 全词书「已记住」条数（跨课），与列表首卡片一致。
  int _rememberedTotal = 0;

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
      rows.add({...lesson, 'rwordnum': n});
    }
    setState(() {
      _rows = rows;
      _rememberedTotal = totalRemembered;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _collectAllRemembered(Map<String, bool> rwords) {
    final out = <Map<String, dynamic>>[];
    for (final lesson in _rows) {
      final words = lesson['words'] as List? ?? [];
      for (final w in words) {
        final wm = Map<String, dynamic>.from(w as Map);
        final key = '${wm['lesson']}|${wm['idx']}';
        if (rwords[key] == true) {
          out.add(wm);
        }
      }
    }
    return out;
  }

  Future<void> _openGlobalRememberedQuiz(BuildContext context) async {
    final rwords = await PrefsStore.instance.loadRemembered();
    final list = _collectAllRemembered(rwords);
    if (!context.mounted) {
      return;
    }
    if (list.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('全词书已记住仅 ${list.length} 个，四选一至少需要 4 个。'),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReciteRememberedQuizPage(
          rememberedWords: list,
        ),
      ),
    );
    if (context.mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.separated(
      itemCount: _rows.length + 1,
      separatorBuilder: (context, index) {
        if (index == 0) {
          return const SizedBox.shrink();
        }
        return const Divider(height: 1);
      },
      itemBuilder: (context, i) {
        if (i == 0) {
          return Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: ListTile(
              leading: const Icon(Icons.quiz_outlined),
              title: const Text('全课已记住测验'),
              subtitle: Text(
                '共 $_rememberedTotal 个已记住单词，打乱顺序四选一（可跨初级/中级各课）',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openGlobalRememberedQuiz(context),
            ),
          );
        }
        final j = i - 1;
        final g = _rows[j];
        final words = g['words'] as List? ?? [];
        final r = g['rwordnum'] as int? ?? 0;
        return ListTile(
          title: Text(g['lesson'] as String? ?? ''),
          subtitle: Text('${g['title'] ?? g['texttitle'] ?? ''}'.replaceAll('\n', ' ')),
          trailing: Text('$r / ${words.length}'),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RecitePage(
                  words: List<Map<String, dynamic>>.from(
                    words.map((e) => Map<String, dynamic>.from(e as Map)),
                  ),
                  lessonTitle: g['lesson'] as String? ?? '',
                  lessonOkey: (g['okey'] as String?)?.trim().toLowerCase() ?? '',
                ),
              ),
            );
          },
        );
      },
    );
  }
}
