import 'package:flutter/material.dart';

import '../basic4_grammar_repository.dart';
import '../japan_ruby.dart';
import '../widgets/japan_html_view.dart';

/// 第 1～48 课 basic4 整合语法（来自 lessons_basic4_grammar_l1_l48.txt）。
class Basic4GrammarPage extends StatefulWidget {
  const Basic4GrammarPage({super.key});

  @override
  State<Basic4GrammarPage> createState() => _Basic4GrammarPageState();
}

class _Basic4GrammarPageState extends State<Basic4GrammarPage> {
  bool _loading = true;
  String? _error;
  final Map<int, GlobalKey> _lessonKeys = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await Basic4GrammarRepository.instance.load();
      for (final lesson in Basic4GrammarRepository.instance.lessons) {
        _lessonKeys.putIfAbsent(lesson.lessonNo, () => GlobalKey());
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickLessonAndScroll() async {
    final lessons = Basic4GrammarRepository.instance.lessons;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: lessons.length,
            itemBuilder: (context, i) {
              final g = lessons[i];
              return ListTile(
                title: Text(g.heading),
                onTap: () => Navigator.pop(context, g.lessonNo),
              );
            },
          ),
        );
      },
    );
    if (picked == null) return;
    if (!mounted) return;
    final key = _lessonKeys[picked];
    final ctx = key?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('基本课文语法'),
        actions: [
          if (!_loading && _error == null)
            IconButton(
              tooltip: '跳转到课',
              icon: const Icon(Icons.list_alt),
              onPressed: _pickLessonAndScroll,
            ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('加载失败：$_error'));
    }

    final repo = Basic4GrammarRepository.instance;
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (repo.introLines.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              repo.introLines.join('\n'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ...repo.lessons.expand((lesson) sync* {
          yield KeyedSubtree(
            key: _lessonKeys[lesson.lessonNo],
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                lesson.heading,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          );
          for (final s in lesson.sentences) {
            yield Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Chip(
                            label: Text('句${s.index}'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          const Spacer(),
                          Text(
                            lesson.lessonId,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      JapanHtmlView(JapanRuby.convert(s.japanese)),
                      if (s.translation.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          '译文',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: colorScheme.secondary,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.translation,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                      if (s.grammar.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '语法',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                s.grammar,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }
        }),
      ],
    );
  }
}
