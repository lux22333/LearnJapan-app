import 'package:flutter/material.dart';

import '../prefs_store.dart';

/// 本课「已记住」单词管理：仅列出已标记项，可一键取消。
class ReciteRememberedManagePage extends StatefulWidget {
  const ReciteRememberedManagePage({
    super.key,
    required this.lessonTitle,
    required this.words,
  });

  final String lessonTitle;
  final List<Map<String, dynamic>> words;

  @override
  State<ReciteRememberedManagePage> createState() =>
      _ReciteRememberedManagePageState();
}

class _ReciteRememberedManagePageState extends State<ReciteRememberedManagePage> {
  Map<String, bool> _rwords = {};
  bool _loading = true;

  static String _rid(Map<String, dynamic> p) =>
      '${p['lesson']}|${p['idx']}';

  static String _kanaLine(Map<String, dynamic> p) {
    final k = p['kana']?.toString() ?? '';
    return k.replaceAll(RegExp(r'@\d+'), '');
  }

  static String _titleLine(Map<String, dynamic> p) {
    final d = p['desc']?.toString().trim();
    if (d != null && d.isNotEmpty) return d;
    return p['word']?.toString() ?? '';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await PrefsStore.instance.loadRemembered();
    if (!mounted) return;
    setState(() {
      _rwords = m;
      _loading = false;
    });
  }

  Future<void> _clearRemembered(String rid) async {
    _rwords.remove(rid);
    await PrefsStore.instance.saveRemembered(_rwords);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.lessonTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final remembered = <Map<String, dynamic>>[];
    for (final w in widget.words) {
      final rid = _rid(w);
      if (_rwords[rid] == true) {
        remembered.add(w);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('已记住 · ${widget.lessonTitle}'),
      ),
      body: remembered.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '本课暂无已记住的单词',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: remembered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = remembered[i];
                final rid = _rid(p);
                return ListTile(
                  title: Text(_titleLine(p)),
                  subtitle: Text(
                    _kanaLine(p),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: TextButton(
                    onPressed: () => _clearRemembered(rid),
                    child: const Text('取消记住'),
                  ),
                );
              },
            ),
    );
  }
}
