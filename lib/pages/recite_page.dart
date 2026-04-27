import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../japan_ruby.dart';
import '../prefs_store.dart';
import '../recite_word_clip_path.dart';
import '../word_clip_audio.dart';
import '../widgets/japan_html_view.dart';
import 'recite_remembered_manage_page.dart';

/// 背词音频日志。过滤：`adb logcat | findstr ReciteAudio`
void _reciteAudioLog(String message) {
  debugPrint('[ReciteAudio] $message');
}

class RecitePage extends StatefulWidget {
  const RecitePage({
    super.key,
    required this.words,
    required this.lessonTitle,
    this.lessonOkey = '',
  });

  final List<Map<String, dynamic>> words;
  final String lessonTitle;

  /// 与 `assets/audio/word/{okey}.mp3` 的课别一致，用于加载 `assets/single_words/{okey}/XXXX.mp3`。
  final String lessonOkey;

  @override
  State<RecitePage> createState() => _RecitePageState();
}

class _RecitePageState extends State<RecitePage> {
  /// 在 [_bootstrap] 完成前为 true，避免首帧访问未初始化的 late 列表（Web/桌面会触发 LateInitializationError）。
  bool _bootstrapping = true;
  List<_QuizItem> _quiz = <_QuizItem>[];
  int _quizId = 0;
  bool _onlyUnremembered = true;
  bool _shuffle = false;
  bool _autoRead = true;
  AudioPlayer? _clipPlayer;
  Map<String, bool> _rwords = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _reciteAudioLog('dispose: dispose clip player');
    unawaited(_clipPlayer?.dispose());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _reciteAudioLog(
      'bootstrap start lesson="${widget.lessonTitle}" words=${widget.words.length} '
      'kIsWeb=$kIsWeb platform=$defaultTargetPlatform',
    );
    _rwords = await PrefsStore.instance.loadRemembered();
    _reciteAudioLog('prefs remembered count=${_rwords.values.where((v) => v).length}');
    _rebuildQuiz(resetPosition: true);
    if (!mounted) return;
    setState(() => _bootstrapping = false);
    _reciteAudioLog('bootstrap UI ready quiz=${_quiz.length} quizId=$_quizId autoRead=$_autoRead');
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
    _reciteAudioLog(
      '_rebuildQuiz shuffle=$_shuffle reset=$resetPosition quizLen=${_quiz.length} quizId=$_quizId',
    );
    if (_quiz.isNotEmpty) {
      _maybeSpeakBack();
    }
    setState(() {});
  }

  void _maybeSpeakBack() {
    if (!_autoRead || _quiz.isEmpty) {
      _reciteAudioLog(
        '_maybeSpeakBack skip: autoRead=$_autoRead quizEmpty=${_quiz.isEmpty}',
      );
      return;
    }
    if (_quizId % 2 == 1) {
      final q = _quiz[_quizId ~/ 2];
      _reciteAudioLog(
        '_maybeSpeakBack play clip: quizId=$_quizId idx=${_quizId ~/ 2}',
      );
      unawaited(_playWordClip(q, showErrorSnack: false));
    } else {
      _reciteAudioLog('_maybeSpeakBack skip: card front (quizId=$_quizId even)');
    }
  }

  /// 仅播放 `assets/single_words/{lessonOkey}/XXXX.mp3`。
  Future<void> _playWordClip(_QuizItem q, {required bool showErrorSnack}) async {
    final path = reciteWordClipAssetPath(widget.lessonOkey, q.wordIdx);
    if (path.isEmpty) {
      _reciteAudioLog('_playWordClip skip: empty path (okey or idx)');
      if (showErrorSnack && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('本课未配置 okey，无法定位切片音频。请从课程列表进入背词。')),
        );
      }
      return;
    }
    try {
      final bundle = DefaultAssetBundle.of(context);
      try {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
        await session.setActive(true);
      } catch (e, st) {
        _reciteAudioLog('AudioSession(clip): $e\n$st');
      }
      _clipPlayer ??= AudioPlayer();
      final p = _clipPlayer!;
      await p.stop();
      await loadWordClipIntoPlayer(p, path, bundle: bundle);
      await p.setSpeed(1);
      await p.seek(Duration.zero);
      _reciteAudioLog('word clip load ok path=$path');
      await p.play();
      await p.playerStateStream
          .firstWhere((s) => s.processingState == ProcessingState.completed)
          .timeout(const Duration(seconds: 60));
      _reciteAudioLog('word clip 播放完成');
    } catch (e, st) {
      _reciteAudioLog('word clip 失败: $e\n$st');
      if (showErrorSnack && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              '无法播放 $path\n'
              '请确认 mp3 已放入工程、pubspec 含 assets/single_words/，并执行 flutter clean 后重新安装（勿仅热重载）。\n$e',
            ),
          ),
        );
      }
    }
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
    _reciteAudioLog('_roll -> quizId=$_quizId parity=${_quizId % 2} (1=背面)');
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

  bool _hasClipForQuiz(_QuizItem q) =>
      reciteWordClipAssetPath(widget.lessonOkey, q.wordIdx).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.lessonTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
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
              onPressed: !_hasClipForQuiz(q)
                  ? null
                  : () {
                      _reciteAudioLog(
                        'AppBar 朗读 ${reciteWordClipAssetPath(widget.lessonOkey, q.wordIdx)}',
                      );
                      unawaited(_playWordClip(q, showErrorSnack: true));
                    },
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
                  subtitle: const Text(
                    '翻到背面时自动播放 assets/single_words 下对应课的切片 MP3；'
                    '无文件则静默跳过（需先运行 tool/split_lesson_word_mp3.py 并重新编译）。',
                  ),
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
    required this.wordIdx,
    required this.tipHtml,
    required this.wordTitleHtml,
    required this.wordSubHtml,
    required this.readKana,
  });

  final String rid;
  final String wordIdx;
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
      wordIdx: p['idx']?.toString() ?? '',
      tipHtml: tip,
      wordTitleHtml: desctitle,
      wordSubHtml: descsubtitle,
      readKana: readKana,
    );
  }
}
