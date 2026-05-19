import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'basic4_grammar_repository.dart';
import 'lesson_repository.dart';
import 'pages/lesson_list_page.dart';
import 'pages/recite_list_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 清掉 just_audio 旧 asset 缓存，避免「缓存文件已存在但内容不完整」时跳过重新拷贝、ExoPlayer 嗅探失败。
  if (!kIsWeb) {
    unawaited(AudioPlayer.clearAssetCache());
  }
  // 不在此处配置 AudioSession：由各页面在播放前按需配置。
  debugPrint('[App] main() LearnJapanApp starting');
  runApp(const LearnJapanApp());
}

class LearnJapanApp extends StatelessWidget {
  const LearnJapanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '标日学习',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const _HomeShell(),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    LessonRepository.instance.load();
    Basic4GrammarRepository.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('标日学习'),
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          LessonListPage(),
          SearchPage(),
          ReciteListPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '课程',
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            label: '搜索',
          ),
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style),
            label: '单词',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
