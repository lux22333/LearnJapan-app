import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../prefs_store.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _importCtrl = TextEditingController();

  @override
  void dispose() {
    _importCtrl.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final text = _importCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      await PrefsStore.instance.importRememberedJson(text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('学习记录已导入')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导入失败：请检查 JSON 格式')),
      );
    }
  }

  Future<void> _export() async {
    final s = await PrefsStore.instance.exportRememberedJson();
    if (s == null || s.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无学习记录')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: s));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '学习记录',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          '「已记住」单词保存在本机，可导出为 JSON 备份或在更换设备时导入。',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _export,
                child: const Text('导出到剪贴板'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _import,
                child: const Text('从文本导入'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _importCtrl,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: '粘贴导出的 JSON',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '关于',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          '数据与排版规则来自开源项目「冰河标日学习日志」。'
          '课文与单词朗读音频打包在应用内（来源：项目 gh-pages）。若需更新音频，可运行 dart run tool/fetch_audio.dart 后重新编译。',
          style: TextStyle(fontSize: 13),
        ),
      ],
    );
  }
}
