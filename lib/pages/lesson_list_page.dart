import 'package:flutter/material.dart';

import '../japan_ruby.dart';
import '../lesson_repository.dart';
import '../widgets/japan_html_view.dart';
import 'item_detail_page.dart';

class LessonListPage extends StatefulWidget {
  const LessonListPage({super.key});

  @override
  State<LessonListPage> createState() => _LessonListPageState();
}

class _LessonListPageState extends State<LessonListPage> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await LessonRepository.instance.load();
      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('加载失败：$_error'));
    }

    final groups = LessonRepository.instance.lessons;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: groups.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final g = groups[i];
        final titleHtml = JapanRuby.convert((g['title'] as String?) ?? '');
        final texttitle = g['texttitle'] as String?;
        final subtitle = g['contitle'] as String?;

        return ListTile(
          title: texttitle != null && texttitle.isNotEmpty
              ? Text(texttitle, style: Theme.of(context).textTheme.titleMedium)
              : JapanHtmlView(titleHtml),
          subtitle: texttitle != null && subtitle != null
              ? Text(subtitle.replaceAll('\n', ' '))
              : null,
          trailing: Text(
            g['lesson'] as String? ?? '',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ItemDetailPage(item: g),
              ),
            );
          },
        );
      },
    );
  }
}
