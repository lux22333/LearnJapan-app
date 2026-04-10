// 从仓库根目录 _data 生成 assets/data/lessons_bundle.json
// 运行（在 learn_japan_flutter 目录下）: dart run tool/build_data.dart

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

void main() {
  final root = Directory.current;
  final dataDir = Directory(p.normalize(p.join(root.parent.path, '_data')));
  final outFile = File(p.join(root.path, 'assets', 'data', 'lessons_bundle.json'));

  final level1 = yamlToJson(loadYaml(File(p.join(dataDir.path, 'lessons.yml')).readAsStringSync()))
      as Map<String, dynamic>;
  final level2 = yamlToJson(loadYaml(File(p.join(dataDir.path, 'mlessons.yml')).readAsStringSync()))
      as Map<String, dynamic>;
  final grammarRaw = File(p.join(dataDir.path, 'grammar.csv')).readAsStringSync();
  final wordsRaw = File(p.join(dataDir.path, 'words.csv')).readAsStringSync();

  final grammar = parseGrammar(grammarRaw);
  final words = parseWords(wordsRaw);

  final bundle = <String, dynamic>{
    'level1': level1,
    'level2': level2,
    'grammar': grammar,
    'words': words,
  };

  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(bundle));
  stdout.writeln('Wrote ${outFile.path} (${outFile.lengthSync()} bytes)');
}

dynamic yamlToJson(dynamic node) {
  if (node is YamlMap) {
    return Map<String, dynamic>.fromEntries(
      node.entries.map((e) => MapEntry(e.key.toString(), yamlToJson(e.value))),
    );
  }
  if (node is YamlList) {
    return node.map<dynamic>((e) => yamlToJson(e)).toList();
  }
  if (node is YamlScalar) {
    return node.value;
  }
  return node;
}

List<Map<String, dynamic>> parseGrammar(String raw) {
  final rows = const CsvToListConverter(
    shouldParseNumbers: false,
  ).convert(raw, eol: '\n');
  if (rows.isEmpty) return [];
  final header = rows.first.map((e) => e.toString().trim()).toList();
  final idxIdx = header.indexOf('idx');
  final lessonIdx = header.indexOf('lesson');
  final exprIdx = header.indexOf('expression');
  final shortIdx = header.indexOf('shortexplain');
  final explIdx = header.indexOf('explanation');
  final out = <Map<String, dynamic>>[];
  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.isEmpty || row.every((c) => c.toString().trim().isEmpty)) continue;
    String cell(int j) => j >= 0 && j < row.length ? row[j].toString().trim() : '';
    out.add({
      'idx': cell(idxIdx),
      'lesson': cell(lessonIdx),
      'expression': cell(exprIdx),
      'shortexplain': cell(shortIdx),
      'explanation': cell(explIdx),
    });
  }
  return out;
}

List<Map<String, dynamic>> parseWords(String raw) {
  final rows = const CsvToListConverter(
    shouldParseNumbers: false,
  ).convert(raw, eol: '\n');
  if (rows.isEmpty) return [];
  final header = rows.first.map((e) => e.toString().trim()).toList();
  final keys = ['kana', 'kanji', 'pos', 'desc', 'word', 'lesson', 'idx'];
  final idxs = keys.map(header.indexOf).toList();
  if (idxs.any((x) => x < 0)) {
    throw StateError('words.csv header mismatch: $header');
  }
  final out = <Map<String, dynamic>>[];
  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.isEmpty) continue;
    final m = <String, dynamic>{};
    for (var k = 0; k < keys.length; k++) {
      final j = idxs[k];
      m[keys[k]] = j < row.length ? row[j].toString().trim() : '';
    }
    out.add(m);
  }
  return out;
}
