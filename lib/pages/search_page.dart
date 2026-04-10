import 'package:flutter/material.dart';

import '../japan_ruby.dart';
import '../lesson_repository.dart';
import '../widgets/japan_html_view.dart';
import 'item_detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  SearchResult _result = SearchResult(words: const [], grammar: const []);
  int _wordLimit = 9;
  int _grammarLimit = 9;

  @override
  void initState() {
    super.initState();
    LessonRepository.instance.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _result = SearchResult(words: const [], grammar: const []);
      });
      return;
    }
    setState(() {
      _wordLimit = 3;
      _grammarLimit = 3;
      _result = LessonRepository.instance.search(q);
    });
  }

  void _moreWords() {
    setState(() => _wordLimit += 5);
  }

  void _moreGrammar() {
    setState(() => _grammarLimit += 5);
  }

  @override
  Widget build(BuildContext context) {
    final words = _result.words.take(_wordLimit).toList();
    final grammar = _result.grammar.take(_grammarLimit).toList();
    final moreWords = _wordLimit < _result.words.length;
    final moreGrammar = _grammarLimit < _result.grammar.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: '搜索单词、语法说明…',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _onChanged,
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (grammar.isNotEmpty) ...[
                const ListTile(
                  title: Text('语法', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ...grammar.map(
                  (g) => ListTile(
                    title: Text(g['expression']?.toString() ?? ''),
                    subtitle: JapanHtmlView(
                      (g['explanation']?.toString() ?? '')
                          .replaceAll('\n', '<br />'),
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ItemDetailPage(item: g),
                        ),
                      );
                    },
                  ),
                ),
                if (moreGrammar)
                  TextButton(
                    onPressed: _moreGrammar,
                    child: const Text('更多语法'),
                  ),
              ],
              if (words.isNotEmpty) ...[
                const ListTile(
                  title: Text('单词', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ...words.map(
                  (w) => ListTile(
                    title: JapanHtmlView(
                      JapanRuby.convert(w['kana']?.toString() ?? ''),
                    ),
                    subtitle: Text(w['desc']?.toString() ?? ''),
                    trailing: JapanHtmlView(
                      JapanRuby.convert(w['word']?.toString() ?? ''),
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ItemDetailPage(item: w),
                        ),
                      );
                    },
                  ),
                ),
                if (moreWords)
                  TextButton(
                    onPressed: _moreWords,
                    child: const Text('更多单词'),
                  ),
              ],
              if (words.isEmpty &&
                  grammar.isEmpty &&
                  _controller.text.trim().isNotEmpty)
                const ListTile(
                  title: Text('无结果'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
