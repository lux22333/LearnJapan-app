import 'package:flutter/material.dart';

import '../lesson_repository.dart';
import '../prefs_store.dart';
import 'recite_page.dart';
import 'recite_remembered_quiz_pick_page.dart';

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
              title: const Text('已记住测验'),
              subtitle: Text(
                '共 $_rememberedTotal 个已记住；可选全部或多课，四选一',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const ReciteRememberedQuizPickPage(),
                  ),
                );
              },
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
