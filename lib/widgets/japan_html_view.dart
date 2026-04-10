import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

/// 渲染 `JapanRuby.convert` 产出的 HTML（ruby / 重音 span）。
class JapanHtmlView extends StatelessWidget {
  const JapanHtmlView(this.html, {super.key, this.textStyle});

  final String html;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final base = textStyle ??
        Theme.of(context).textTheme.bodyMedium ??
        const TextStyle();
    return HtmlWidget(
      html,
      textStyle: base,
    );
  }
}
