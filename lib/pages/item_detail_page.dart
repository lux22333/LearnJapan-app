import 'package:flutter/material.dart';

import '../japan_ruby.dart';
import '../prefs_store.dart';
import '../widgets/japan_html_view.dart';
import 'lesson_detail_shell.dart';

/// 对应 Ionic `item-detail`：课程 / 单词 / 语法条目。
class ItemDetailPage extends StatelessWidget {
  const ItemDetailPage({super.key, required this.item});

  final Map<String, dynamic> item;

  static Map<String, dynamic> _map(dynamic x) =>
      Map<String, dynamic>.from(x as Map);

  String _nl(String? s) =>
      (s ?? '').replaceAll(r'\n', '<br />').replaceAll('\n', '<br />');

  @override
  Widget build(BuildContext context) {
    if (item['basic4'] != null) {
      return _buildPrimaryLesson(context);
    }
    if (item['conversation'] != null) {
      return _buildMiddleLesson(context);
    }
    if (item['expression'] != null) {
      return _buildGrammar(context);
    }
    return _buildWord(context);
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _buildPrimaryLesson(BuildContext context) {
    final basic4 = item['basic4'] as List? ?? [];
    final basicc = item['basicc'] as List? ?? [];
    final contextLines = item['context'] as List? ?? [];
    final grammar = item['grammar'] as List? ?? [];
    final words = item['words'] as List? ?? [];

    return LessonDetailShell(
      item: item,
      title: JapanHtmlView(
        JapanRuby.convert((item['title'] as String?) ?? ''),
      ),
      body: ListView(
        children: [
          _sectionTitle(context, '基本课文'),
          ...basic4.asMap().entries.map(
                (e) => ListTile(
                  leading: Text('${e.key + 1}.'),
                  title: JapanHtmlView(JapanRuby.convert(e.value.toString())),
                ),
              ),
          const Divider(),
          ...basicc.map(
            (t) => ListTile(
              title: JapanHtmlView(JapanRuby.convert(t.toString())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: JapanHtmlView(
              JapanRuby.convert((item['contitle'] as String?) ?? ''),
            ),
          ),
          ...contextLines.map((t) {
            final s = t.toString();
            if (s.trim() == '---') {
              return const Divider(height: 24);
            }
            return ListTile(
              title: JapanHtmlView(JapanRuby.convert(s)),
            );
          }),
          _sectionTitle(context, '语法'),
          ...grammar.map(
            (g) {
              final gm = _map(g);
              return ListTile(
                title: Text(gm['expression']?.toString() ?? ''),
                subtitle: JapanHtmlView(
                  _nl(gm['explanation']?.toString()),
                ),
                trailing: Text(
                  gm['shortexplain']?.toString() ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ItemDetailPage(item: gm),
                    ),
                  );
                },
              );
            },
          ),
          _sectionTitle(context, '单词'),
          ...words.map(
            (w) {
              final wm = _map(w);
              return ListTile(
                title: JapanHtmlView(
                  JapanRuby.convert(wm['kana']?.toString() ?? ''),
                ),
                subtitle: JapanHtmlView(
                  JapanRuby.convert(wm['desc']?.toString() ?? ''),
                ),
                trailing: JapanHtmlView(
                  JapanRuby.convert(wm['word']?.toString() ?? ''),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ItemDetailPage(item: wm),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMiddleLesson(BuildContext context) {
    final conversation = item['conversation'] as List? ?? [];
    final text = item['text'] as List? ?? [];
    final grammar = item['grammar'] as List? ?? [];
    final words = item['words'] as List? ?? [];

    return LessonDetailShell(
      item: item,
      title: JapanHtmlView(
        JapanRuby.convert((item['texttitle'] as String?) ?? ''),
      ),
      body: ListView(
        children: [
          _sectionTitle(context, (item['contitle'] as String?) ?? ''),
          ...conversation.map(
            (t) => ListTile(
              title: JapanHtmlView(JapanRuby.convert(t.toString())),
            ),
          ),
          _sectionTitle(context, (item['texttitle'] as String?) ?? ''),
          ...text.map(
            (t) => ListTile(
              title: JapanHtmlView(JapanRuby.convert(t.toString())),
            ),
          ),
          _sectionTitle(context, '语法'),
          ...grammar.map(
            (g) {
              final gm = _map(g);
              return ListTile(
                title: Text(gm['expression']?.toString() ?? ''),
                subtitle: JapanHtmlView(
                  _nl(gm['explanation']?.toString()),
                ),
                trailing: Text(gm['shortexplain']?.toString() ?? ''),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ItemDetailPage(item: gm),
                    ),
                  );
                },
              );
            },
          ),
          _sectionTitle(context, '单词'),
          ...words.map(
            (w) {
              final wm = _map(w);
              return ListTile(
                title: JapanHtmlView(
                  JapanRuby.convert(wm['kana']?.toString() ?? ''),
                ),
                subtitle: JapanHtmlView(
                  JapanRuby.convert(wm['desc']?.toString() ?? ''),
                ),
                trailing: JapanHtmlView(
                  JapanRuby.convert(wm['word']?.toString() ?? ''),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ItemDetailPage(item: wm),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGrammar(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(item['expression']?.toString() ?? '语法'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('表达'),
            subtitle: Text(item['expression']?.toString() ?? ''),
          ),
          ListTile(
            title: const Text('简义'),
            subtitle: Text(
              (item['shortexplain'] as String?)?.isNotEmpty == true
                  ? item['shortexplain'].toString()
                  : '<暂无>',
            ),
          ),
          const SizedBox(height: 8),
          Text('解释', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          JapanHtmlView(_nl(item['explanation']?.toString())),
          ListTile(
            title: const Text('课本'),
            subtitle: Text(item['lesson']?.toString() ?? ''),
          ),
        ],
      ),
    );
  }

  Widget _buildWord(BuildContext context) {
    return _WordDetailBody(item: item);
  }
}

class _WordDetailBody extends StatefulWidget {
  const _WordDetailBody({required this.item});

  final Map<String, dynamic> item;

  @override
  State<_WordDetailBody> createState() => _WordDetailBodyState();
}

class _WordDetailBodyState extends State<_WordDetailBody> {
  bool _remember = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lesson = widget.item['lesson']?.toString();
    final idx = widget.item['idx']?.toString();
    if (lesson == null || idx == null) return;
    final key = '$lesson|$idx';
    final all = await PrefsStore.instance.loadRemembered();
    setState(() {
      _remember = all[key] ?? false;
    });
  }

  Future<void> _save() async {
    final lesson = widget.item['lesson']?.toString();
    final idx = widget.item['idx']?.toString();
    if (lesson == null || idx == null) return;
    final key = '$lesson|$idx';
    final all = await PrefsStore.instance.loadRemembered();
    all[key] = _remember;
    await PrefsStore.instance.saveRemembered(all);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.item;
    return Scaffold(
      appBar: AppBar(
        title: JapanHtmlView(JapanRuby.convert(w['word']?.toString() ?? '')),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.translate),
            title: const Text('意思'),
            subtitle: Text(w['desc']?.toString() ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('词性'),
            subtitle: Text(w['pos']?.toString() ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over),
            title: const Text('发音'),
            subtitle: JapanHtmlView(JapanRuby.convert(w['kana']?.toString() ?? '')),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book),
            title: const Text('课本'),
            subtitle: Text(w['lesson']?.toString() ?? ''),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.check_circle_outline),
            title: const Text('已记住'),
            value: _remember,
            onChanged: (v) {
              setState(() => _remember = v);
              _save();
            },
          ),
        ],
      ),
    );
  }
}
