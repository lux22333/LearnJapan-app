import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../japan_ruby.dart';
import '../prefs_store.dart';
import '../widgets/japan_html_view.dart';
import 'recite_remembered_manage_page.dart';

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
  /// Android：`setLanguage('ja-JP')` 为 1 才表示当前引擎已接受日语（选错「语音识别」引擎时常为 0）。
  bool _ttsJaLanguageApplied = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    unawaited(_tts.stop());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _configureTts();
    _rwords = await PrefsStore.instance.loadRemembered();
    _rebuildQuiz(resetPosition: true);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_maybeWarnTtsSetup());
    });
  }

  /// 尽量使用带日语离线包的 Google TTS，并请求音频焦点（部分机型无声与此有关）。
  Future<void> _configureTts() async {
    _tts.setErrorHandler((msg) => debugPrint('TTS error: $msg'));
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final engines = await _tts.getEngines;
        if (engines is List) {
          for (final e in engines) {
            if (e == 'com.google.android.tts') {
              await _tts.setEngine('com.google.android.tts');
              break;
            }
          }
        }
      } catch (e, st) {
        debugPrint('TTS setEngine: $e\n$st');
      }
    }
    final langResult = await _tts.setLanguage('ja-JP');
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _ttsJaLanguageApplied = langResult == 1;
    }
    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.5);
  }

  Future<void> _maybeWarnTtsSetup() async {
    if (!mounted || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    if (!_ttsJaLanguageApplied) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            '当前「文字转语音」引擎不支持日语朗读。'
            '请勿选「Google 语音识别」（那是输入法听写用的）；'
            '请改为「Google 文字转语音引擎」或 Play 商店里的「Speech Services by Google」，'
            '并在该引擎设置里安装日语语音包。',
          ),
          duration: Duration(seconds: 12),
        ),
      );
      return;
    }

    try {
      final installed = await _tts.isLanguageInstalled('ja-JP');
      if (installed == true || !mounted) return;
    } catch (_) {
      return;
    }
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          '日语离线朗读包未就绪（联网时部分机型仍可朗读）。'
          '请在「文字转语音输出」里点进 Google 引擎设置，下载日语语音数据。',
        ),
        duration: Duration(seconds: 8),
      ),
    );
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
    await _tts.speak(text, focus: true);
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
          if (!front)
            IconButton(
              tooltip: '朗读',
              onPressed: q.readKana.isEmpty ? null : () => _speak(q.readKana),
              icon: const Icon(Icons.volume_up),
            ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.only(left: 8, right: 12),
            ),
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ReciteRememberedManagePage(
                    lessonTitle: widget.lessonTitle,
                    words: widget.words,
                  ),
                ),
              );
              if (!mounted) return;
              _rwords = await PrefsStore.instance.loadRemembered();
              setState(() {});
            },
            child: Text(summary),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                        ],
                      ],
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('本词已记住'),
                  subtitle: const Text('关闭即恢复为未记住'),
                  value: remember,
                  onChanged: (v) => _toggleRemember(v),
                ),
                SwitchListTile(
                  title: const Text('跳过已记住'),
                  subtitle: const Text('也可点右上角进度，在列表里取消已记住'),
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
          ),
          Material(
            elevation: 3,
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _roll(-1),
                        child: const Text('上一张'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _roll(1),
                        child: const Text('下一张'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
