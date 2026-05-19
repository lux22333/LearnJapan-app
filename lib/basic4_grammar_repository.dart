import 'package:flutter/services.dart' show rootBundle;

/// 基本课文（basic4）单句语法说明。
class Basic4GrammarSentence {
  const Basic4GrammarSentence({
    required this.index,
    required this.japanese,
    required this.translation,
    required this.grammar,
  });

  final int index;
  final String japanese;
  final String translation;
  final String grammar;
}

/// 一课四条 basic4 语法。
class Basic4GrammarLesson {
  const Basic4GrammarLesson({
    required this.lessonId,
    required this.lessonNo,
    required this.sentences,
  });

  final String lessonId;
  final int lessonNo;
  final List<Basic4GrammarSentence> sentences;

  String get heading => '第${lessonNo.toString().padLeft(2, '0')}课 ($lessonId)';
}

/// 解析 `assets/data/lessons_basic4_grammar_l1_l48.txt`。
class Basic4GrammarRepository {
  Basic4GrammarRepository._();

  static final Basic4GrammarRepository instance = Basic4GrammarRepository._();

  static const assetPath = 'assets/data/lessons_basic4_grammar_l1_l48.txt';

  static final _lessonHeader = RegExp(r'^=+\s*第(\d+)课\s*\((\w+)\)\s*=+$');
  static final _sentenceStart = RegExp(r'^【句(\d+)】(.+)$');

  List<String>? _introLines;
  List<Basic4GrammarLesson>? _lessons;

  List<String> get introLines => _introLines ?? const [];

  Future<void> load() async {
    if (_lessons != null) return;
    final raw = await rootBundle.loadString(assetPath);
    _parse(raw);
  }

  List<Basic4GrammarLesson> get lessons {
    assert(_lessons != null, 'Call load() first');
    return _lessons!;
  }

  void _parse(String raw) {
    final intro = <String>[];
    final out = <Basic4GrammarLesson>[];
    Basic4GrammarLesson? currentLesson;
    Basic4GrammarSentence? currentSentence;
    final currentSentences = <Basic4GrammarSentence>[];

    void flushSentence() {
      if (currentLesson == null || currentSentence == null) return;
      currentSentences.add(currentSentence!);
      currentSentence = null;
    }

    void flushLesson() {
      flushSentence();
      if (currentLesson == null) return;
      out.add(Basic4GrammarLesson(
        lessonId: currentLesson!.lessonId,
        lessonNo: currentLesson!.lessonNo,
        sentences: List.unmodifiable(currentSentences),
      ));
      currentSentences.clear();
      currentLesson = null;
    }

    for (final line in raw.split('\n')) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) {
        continue;
      }

      final lessonMatch = _lessonHeader.firstMatch(trimmed);
      if (lessonMatch != null) {
        flushLesson();
        currentLesson = Basic4GrammarLesson(
          lessonId: lessonMatch.group(2)!,
          lessonNo: int.parse(lessonMatch.group(1)!),
          sentences: const [],
        );
        continue;
      }

      if (currentLesson == null) {
        intro.add(trimmed);
        continue;
      }

      final sentenceMatch = _sentenceStart.firstMatch(trimmed);
      if (sentenceMatch != null) {
        flushSentence();
        currentSentence = Basic4GrammarSentence(
          index: int.parse(sentenceMatch.group(1)!),
          japanese: sentenceMatch.group(2)!.trim(),
          translation: '',
          grammar: '',
        );
        continue;
      }

      if (currentSentence == null) {
        continue;
      }

      if (trimmed.startsWith('译文：')) {
        final prev = currentSentence!;
        currentSentence = Basic4GrammarSentence(
          index: prev.index,
          japanese: prev.japanese,
          translation: trimmed.substring(3).trim(),
          grammar: prev.grammar,
        );
      } else if (trimmed.startsWith('语法：')) {
        final prev = currentSentence!;
        currentSentence = Basic4GrammarSentence(
          index: prev.index,
          japanese: prev.japanese,
          translation: prev.translation,
          grammar: trimmed.substring(3).trim(),
        );
      }
    }

    flushLesson();

    _introLines = List.unmodifiable(intro);
    _lessons = List.unmodifiable(out);
  }
}
