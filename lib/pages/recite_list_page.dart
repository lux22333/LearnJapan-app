import 'package:flutter/material.dart';

import '../lesson_repository.dart';
import '../prefs_store.dart';
import 'recite_page.dart';

class ReciteListPage extends StatefulWidget {
  const ReciteListPage({super.key});

  @override
  State<ReciteListPage> createState() => _ReciteListPageState();
}

class _ReciteListPageState extends State<ReciteListPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];

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
    for (final lesson in data) {
      final words = lesson['words'] as List? ?? [];
      var n = 0;
      for (final w in words) {
        final wm = w as Map;
        final key = '${wm['lesson']}|${wm['idx']}';
        if (rwords[key] == true) n++;
      }
      rows.add({...lesson, 'rwordnum': n});
    }
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.separated(
      itemCount: _rows.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final g = _rows[i];
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
                ),
              ),
            );
          },
        );
      },
    );
  }
}
