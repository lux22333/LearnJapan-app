/// 与 Ionic `japan-ruby.ts` / `japan.ts` 一致的假名标注与重音 HTML 转换。
class JapanRuby {
  JapanRuby._();

  static const _accentStyle = 'color:#c62828;font-weight:600;';

  /// 重音型标签（与红色高亮同色、略小），附在假名后，如「1型」「0型」。
  static const _accentTypeStyle =
      'color:#c62828;font-size:0.82em;font-weight:500;margin-left:5px;white-space:nowrap;';

  static String _accentTypeLabel(int accentNum) =>
      '<span style="$_accentTypeStyle">${accentNum}型</span>';

  /// 按「音拍」切分：`start` 为从 1 计数的起始音拍；`len` 有值时截取固定音拍数，否则取剩余全部。
  /// 旧实现把 `{start}` 套在外层捕获组上，导致 `_getChar(s,1,1)` 先吞掉第 1 拍再取第 2 拍，
  /// 「ノート@1」会变成高亮「ー」+「ト」而丢失「ノ」。
  static String? _getChar(String sentence, int start, [int? len]) {
    if (start < 1) return null;
    final skip = start - 1;
    final lenstr = len == null ? '*' : '{$len}';
    final re = RegExp(
      '(?:.[ゅょゃュョャ]?){$skip}((?:.[ゅょゃュョャ]?)$lenstr)',
    );
    final m = re.firstMatch(sentence);
    return m?.group(1);
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
            return '${a ?? ''}<span style="$_accentStyle">${b ?? ''}</span>'
                '${_accentTypeLabel(num)}';
          }
          if (num == 1) {
            final a = _getChar(sen, 1, 1);
            final rest = _getChar(sen, 2);
            return '<span style="$_accentStyle">${a ?? ''}</span>${rest ?? ''}'
                '${_accentTypeLabel(num)}';
          }
          final first = _getChar(sen, 1, 1);
          final mid = _getChar(sen, 2, num - 1);
          final last = _getChar(sen, num + 1);
          return '${first ?? ''}<span style="$_accentStyle">${mid ?? ''}</span>${last ?? ''}'
              '${_accentTypeLabel(num)}';
        });
      }
    } catch (_) {
      // 与 TS 一致：出错时返回原文
    }
    return content;
  }
}
