import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../japan_ruby.dart';
import '../prefs_store.dart';
import '../widgets/japan_html_view.dart';

class RecitePage extends StatefulWidget {
  const RecitePage({
    super.key,
    required this.words,
    required this.lessonTitle,
  });

  final List<Map<String, dynamic>> words;
  final String lessonTitle;

  @override
  State<RecitePage> createState() => _RecitePageState();
}

class _RecitePageState extends State<RecitePage> {
  late List<_QuizItem> _quiz;
  int _quizId = 0;
  bool _onlyUnremembered = true;
  bool _shuffle = false;
  bool _autoRead = true;
  final _tts = FlutterTts();
  Map<String, bool> _rwords = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _tts.setLanguage('ja-JP');
    _rwords = await PrefsStore.instance.loadRemembered();
    _rebuildQuiz(resetPosition: true);
  }

  void _rebuildQuiz({bool resetPosition = false}) {
    var list = widget.words.map(_QuizItem.fromRaw).toList();
    if (_shuffle) {
      list = [...list]..shuffle();
    }
    _quiz = list;
    if (resetPosition || _quizId >= _quiz.length * 2) {
      _quizId = 0;
    }
    if (_quiz.isNotEmpty) {
      _maybeSpeakBack();
    }
    setState(() {});
  }

  void _maybeSpeakBack() {
    if (!_autoRead || _quiz.isEmpty) return;
    if (_quizId % 2 == 1) {
      _speak(_quiz[_quizId ~/ 2].readKana);
    }
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  int _rememberedCount() {
    var c = 0;
    for (final q in _quiz) {
      if (_rwords[q.rid] == true) c++;
    }
    return c;
  }

  void _roll(int delta) {
    final n = _quiz.length;
    if (n == 0) return;
    var next = _quizId + delta;
    if (next < 0) next = 0;
    if (next >= n * 2) next = n * 2 - 1;

    if (_onlyUnremembered) {
      var guard = 0;
      while (guard < n * 4 && next >= 0 && next < n * 2) {
        final q = _quiz[next ~/ 2];
        if (_rwords[q.rid] != true) break;
        next += delta.sign;
        if (next < 0) next = 0;
        if (next >= n * 2) next = n * 2 - 1;
        guard++;
      }
    }

    _quizId = next;
    _maybeSpeakBack();
    setState(() {});
  }

  Future<void> _toggleRemember(bool v) async {
    if (_quiz.isEmpty) return;
    final q = _quiz[_quizId ~/ 2];
    if (v) {
      _rwords[q.rid] = true;
    } else {
      _rwords.remove(q.rid);
    }
    await PrefsStore.instance.saveRemembered(_rwords);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_quiz.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.lessonTitle)),
        body: const Center(child: Text('本课无单词')),
      );
    }
    final idx = (_quizId ~/ 2).clamp(0, _quiz.length - 1);
    final q = _quiz[idx];
    final front = _quizId % 2 == 0;
    final summary = '${idx + 1}/${_quiz.length} (${_rememberedCount()})';
    final remember = _rwords[q.rid] == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lessonTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text(summary)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (front)
                    JapanHtmlView(q.tipHtml)
                  else ...[
                    JapanHtmlView(q.wordTitleHtml),
                    const SizedBox(height: 8),
                    JapanHtmlView(q.wordSubHtml),
                    TextButton.icon(
                      onPressed: () => _speak(q.readKana),
                      icon: const Icon(Icons.volume_up),
                      label: const Text('朗读'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _roll(1),
                  child: const Text('下一张'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _roll(-1),
                  child: const Text('上一张'),
                ),
              ),
            ],
          ),
          SwitchListTile(
            title: const Text('本词已记住'),
            value: remember,
            onChanged: (v) => _toggleRemember(v),
          ),
          SwitchListTile(
            title: const Text('跳过已记住'),
            value: _onlyUnremembered,
            onChanged: (v) {
              setState(() => _onlyUnremembered = v);
              _rebuildQuiz();
            },
          ),
          SwitchListTile(
            title: const Text('自动朗读（背面）'),
            value: _autoRead,
            onChanged: (v) => setState(() => _autoRead = v),
          ),
          SwitchListTile(
            title: const Text('随机顺序'),
            value: _shuffle,
            onChanged: (v) {
              setState(() => _shuffle = v);
              _rebuildQuiz(resetPosition: true);
            },
          ),
        ],
      ),
    );
  }
}

class _QuizItem {
  _QuizItem({
    required this.rid,
    required this.tipHtml,
    required this.wordTitleHtml,
    required this.wordSubHtml,
    required this.readKana,
  });

  final String rid;
  final String tipHtml;
  final String wordTitleHtml;
  final String wordSubHtml;
  final String readKana;

  static _QuizItem fromRaw(Map<String, dynamic> p) {
    final kanaHtml = JapanRuby.convert(p['kana']?.toString() ?? '');
    final displayHtml = JapanRuby.convert(p['word']?.toString() ?? '');
    final kanji = p['kanji']?.toString() ?? '';
    final desctitle = kanji.isEmpty
        ? '<span class="japan">$kanaHtml</span>'
        : '<span class="japan">$displayHtml</span>';
    final descsubtitle =
        '<span class="japan">$kanaHtml</span><span class="card-pos">[${p['pos']}]</span>';
    final pos = p['pos']?.toString() ?? '';
    final posShort = pos.isNotEmpty ? String.fromCharCode(pos.runes.first) : '';
    final tip =
        "<span class='card-explain'>${p['desc']}</span><span class='card-pos'>[$posShort]</span>";

    final rawKana = p['kana']?.toString() ?? '';
    final readKana = rawKana.replaceAll(RegExp(r'@\d+'), '').replaceAll(
          RegExp(r'[^\u3040-\u309f\u30a0-\u30ff]'),
          '',
        );

    final rid = '${p['lesson']}|${p['idx']}';

    return _QuizItem(
      rid: rid,
      tipHtml: tip,
      wordTitleHtml: desctitle,
      wordSubHtml: descsubtitle,
      readKana: readKana,
    );
  }
}
