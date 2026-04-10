// 从 GitHub gh-pages 下载课文/单词 MP3 到 assets/audio/
// 运行: dart run tool/fetch_audio.dart
// 可选: dart run tool/fetch_audio.dart --force  （覆盖已存在文件）

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const _base =
    'https://raw.githubusercontent.com/wizicer/LearnJapan/gh-pages/assets/audio';

Future<List<int>?> _download(String url, {int retries = 4}) async {
  for (var i = 0; i < retries; i++) {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 120));
      if (res.statusCode == 200) return res.bodyBytes;
      if (res.statusCode == 404) return null;
    } catch (_) {
      if (i == retries - 1) rethrow;
      await Future<void>.delayed(Duration(seconds: 1 << i));
    }
  }
  return null;
}

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final root = Directory.current;
  final bundle = File(p.join(root.path, 'assets', 'data', 'lessons_bundle.json'));
  final data =
      jsonDecode(bundle.readAsStringSync()) as Map<String, dynamic>;
  final level1 = data['level1'] as Map<String, dynamic>;
  final level2 = data['level2'] as Map<String, dynamic>;
  final keys = [...level1.keys, ...level2.keys]..sort();

  final lessonDir = Directory(p.join(root.path, 'assets', 'audio', 'lesson'));
  final wordDir = Directory(p.join(root.path, 'assets', 'audio', 'word'));
  lessonDir.createSync(recursive: true);
  wordDir.createSync(recursive: true);

  var ok = 0;
  var skip = 0;
  var fail = 0;

  for (final okey in keys) {
    for (final type in ['lesson', 'word']) {
      final url = '$_base/$type/$okey.mp3';
      final dir = type == 'lesson' ? lessonDir : wordDir;
      final out = File(p.join(dir.path, '$okey.mp3'));
      if (out.existsSync() && !force) {
        skip++;
        continue;
      }
      stdout.write('$type/$okey.mp3 ... ');
      try {
        final bytes = await _download(url);
        if (bytes == null) {
          stdout.writeln('HTTP 404');
          fail++;
          continue;
        }
        await out.writeAsBytes(bytes);
        stdout.writeln('${bytes.length} bytes');
        ok++;
      } catch (e) {
        stdout.writeln('error: $e');
        if (out.existsSync()) {
          await out.delete();
        }
        fail++;
      }
    }
  }
  stdout.writeln('Done. downloaded: $ok, skipped: $skip, failed: $fail');
  if (fail > 0) {
    exitCode = 1;
  }
}
