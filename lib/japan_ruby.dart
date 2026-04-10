/// 与 Ionic `japan-ruby.ts` / `japan.ts` 一致的假名标注与重音 HTML 转换。
class JapanRuby {
  JapanRuby._();

  static const _accentStyle = 'color:#c62828;font-weight:600;';

  static String? _getChar(String sentence, int start, [int? len]) {
    final lenstr = len == null ? '*' : '{$len}';
    final re = RegExp('(.[ゅょゃュョャ]?)' '{$start}' '((.[ゅょゃュョャ]?)$lenstr)');
    final m = re.firstMatch(sentence);
    return m?.group(2);
  }

  static String convert(String? content) {
    if (content == null || content.isEmpty) return '';
    try {
      if (content.contains('!')) {
        final c = content.replaceAllMapped(
          RegExp(r'!(.*?)\((.*?)\)'),
          (m) => '<rt></rt>${m[1]}<rt>${m[2]}</rt>',
        );
        return '<ruby>$c</ruby>';
      }
      if (content.contains('@')) {
        final re = RegExp(r'([\u3040-\u309f\u30a0-\u30ff]*)@((?:\d{1,2})?)');
        return content.replaceAllMapped(re, (m) {
          final sen = m[1]!;
          final numStr = m[2];
          if (numStr == null || numStr.isEmpty) {
            return sen;
          }
          final num = int.parse(numStr);
          if (num == 0) {
            final a = _getChar(sen, 1, 1);
            final b = _getChar(sen, 2);
            return '${a ?? ''}<span style="$_accentStyle">${b ?? ''}</span>';
          }
          if (num == 1) {
            final a = _getChar(sen, 1, 1);
            final rest = _getChar(sen, 2);
            return '<span style="$_accentStyle">${a ?? ''}</span>${rest ?? ''}';
          }
          final first = _getChar(sen, 1, 1);
          final mid = _getChar(sen, 2, num - 1);
          final last = _getChar(sen, num);
          return '${first ?? ''}<span style="$_accentStyle">${mid ?? ''}</span>${last ?? ''}';
        });
      }
    } catch (_) {
      // 与 TS 一致：出错时返回原文
    }
    return content;
  }
}
