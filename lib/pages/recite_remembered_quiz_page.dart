import 'dart:async';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../japan_ruby.dart';
import '../recite_word_clip_path.dart';
import '../word_clip_audio.dart';
import '../widgets/japan_html_view.dart';

class _McQuestion {
  _McQuestion({
    required this.correct,
    required this.options,
  });

  final Map<String, dynamic> correct;
  /// 四个选项（已打乱），每项对应一词，含 idx / lesson 等。
  final List<Map<String, dynamic>> options;
}

/// 对已记住单词（可跨多课）：中文释义四选一，选项可播放对应日语切片。
/// 每词按 [wordLessonFieldToOkey] 解析 `lesson` 字段定位 `assets/single_words/...`。
class ReciteRememberedQuizPage extends StatefulWidget {
  const ReciteRememberedQuizPage({
    super.key,
    required this.rememberedWords,
  });

  final List<Map<String, dynamic>> rememberedWords;

  @override
  State<ReciteRememberedQuizPage> createState() => _ReciteRememberedQuizPageState();
}

class _ReciteRememberedQuizPageState extends State<ReciteRememberedQuizPage> {
  final Random _rng = Random();
  List<_McQuestion> _questions = [];
  int _qi = 0;
  AudioPlayer? _clipPlayer;
  bool _clipBusy = false;

  static String _rid(Map<String, dynamic> p) =>
      '${p['lesson']}|${p['idx']}';

  static String _kanaLine(Map<String, dynamic> p) {
    final k = p['kana']?.toString() ?? '';
    return k.replaceAll(RegExp(r'@\d+'), '');
  }

  static String _chineseLine(Map<String, dynamic> p) {
    final d = p['desc']?.toString().trim();
    if (d != null && d.isNotEmpty) {
      return d;
    }
    return p['word']?.toString() ?? '';
  }

  static String _promptHtml(Map<String, dynamic> p) {
    final word = p['word']?.toString() ?? '';
    if (word.isNotEmpty) {
      return JapanRuby.convert(word);
    }
    return JapanRuby.convert(p['kana']?.toString() ?? '');
  }

  @override
  void initState() {
    super.initState();
    _buildQuestions();
  }

  @override
  void dispose() {
    unawaited(_clipPlayer?.dispose());
    super.dispose();
  }

  void _buildQuestions() {
    final pool = widget.rememberedWords;
    final qs = <_McQuestion>[];
    for (final w in pool) {
      final others = pool.where((x) => _rid(x) != _rid(w)).toList()..shuffle(_rng);
      final distractors = <Map<String, dynamic>>[];
      final usedCn = <String>{_chineseLine(w)};
      for (final o in others) {
        if (distractors.length >= 3) {
          break;
        }
        final cn = _chineseLine(o);
        if (usedCn.contains(cn)) {
          continue;
        }
        usedCn.add(cn);
        distractors.add(o);
      }
      for (final o in others) {
        if (distractors.length >= 3) {
          break;
        }
        if (distractors.any((d) => _rid(d) == _rid(o))) {
          continue;
        }
        distractors.add(o);
      }
      final opts = [w, ...distractors.take(3)]..shuffle(_rng);
      if (opts.length < 4) {
        continue;
      }
      qs.add(_McQuestion(correct: w, options: opts));
    }
    qs.shuffle(_rng);
    _questions = qs;
  }

  String _clipPath(Map<String, dynamic> w) {
    final okey = wordLessonFieldToOkey(w['lesson']?.toString());
    return reciteWordClipAssetPath(okey, w['idx']?.toString() ?? '');
  }

  bool _hasClip(Map<String, dynamic> w) => _clipPath(w).isNotEmpty;

  Future<void> _playClip(Map<String, dynamic> w) async {
    final path = _clipPath(w);
    if (path.isEmpty || _clipBusy) {
      return;
    }
    setState(() => _clipBusy = true);
    try {
      final bundle = DefaultAssetBundle.of(context);
      try {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
        await session.setActive(true);
      } catch (_) {}
      _clipPlayer ??= AudioPlayer();
      final p = _clipPlayer!;
      await p.stop();
      await loadWordClipIntoPlayer(p, path, bundle: bundle);
      await p.setSpeed(1);
      await p.seek(Duration.zero);
      await p.play();
      await p.playerStateStream
          .firstWhere((s) => s.processingState == ProcessingState.completed)
          .timeout(const Duration(seconds: 60));
    } catch (e, st) {
      debugPrint('[RememberedQuiz] play failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('无法播放：$path')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _clipBusy = false);
      }
    }
  }

  void _onPick(Map<String, dynamic> picked) {
    if (_questions.isEmpty || _qi >= _questions.length) {
      return;
    }
    final q = _questions[_qi];
    if (_rid(picked) == _rid(q.correct)) {
      setState(() => _qi++);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('选择错误')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rememberedWords.length < 4) {
      return Scaffold(
        appBar: AppBar(title: const Text('已记住 · 全课测验')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '全词书中已记住单词少于 4 个，无法组成四选一。\n'
              '请在各课背词中标记「已记住」后再来。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('已记住 · 全课测验')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('暂无可用题目（请确认词目含 lesson/idx 且切片资源齐全）。'),
          ),
        ),
      );
    }

    final done = _qi >= _questions.length;
    final q = done ? _questions.last : _questions[_qi];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('已记住 · 全课测验'),
            if (!done)
              Text(
                '${_qi + 1} / ${_questions.length}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                    ),
              ),
          ],
        ),
      ),
      body: done
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, size: 56, color: Colors.green),
                  const SizedBox(height: 16),
                  Text(
                    '本轮 ${_questions.length} 题已完成',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _buildQuestions();
                        _qi = 0;
                      });
                    },
                    child: const Text('再来一轮'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        JapanHtmlView(_promptHtml(q.correct)),
                        const SizedBox(height: 6),
                        Text(
                          _kanaLine(q.correct),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        if ((q.correct['lesson']?.toString() ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '课：${q.correct['lesson']}',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          '的中文意思是',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _clipBusy || !_hasClip(q.correct)
                                ? null
                                : () => unawaited(_playClip(q.correct)),
                            icon: const Icon(Icons.volume_up),
                            label: const Text('播放题目单词'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '请选择一个中文释义',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                ...q.options.map((opt) {
                  final cn = _chineseLine(opt);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _onPick(opt),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  cn,
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
