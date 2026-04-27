/// 从词目 `lesson` 字段（初级 `001`、中级 `m011` 等）推导 `okey`（`l1`、`m1`），与 `lesson_repository` 的 lkey 一致。
String wordLessonFieldToOkey(String? lessonField) {
  final s = lessonField?.trim() ?? '';
  if (s.isEmpty) {
    return '';
  }
  if (s.startsWith('m')) {
    if (s.length < 3) {
      return '';
    }
    final head = s.substring(0, 3);
    final n = int.tryParse(head.substring(1));
    if (n == null) {
      return '';
    }
    return 'm$n';
  }
  final n = int.tryParse(s);
  if (n == null) {
    return '';
  }
  return 'l$n';
}

/// 背词 / 单词详情：逐词切片 MP3（`tool/split_lesson_word_mp3.py` 输出）。
/// `assets/single_words/{okey}/{idx4}.mp3`
String reciteWordClipAssetPath(String lessonOkey, String idxStr) {
  final o = lessonOkey.trim().toLowerCase();
  if (o.isEmpty) {
    return '';
  }
  final n = int.tryParse(idxStr.trim());
  if (n == null) {
    return '';
  }
  return 'assets/single_words/$o/${n.toString().padLeft(4, '0')}.mp3';
}
