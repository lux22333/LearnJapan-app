import 'dart:io';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// 先读 [AssetBundle] 全量字节再 [setFilePath]，避免 ExoPlayer 读到 just_audio 不完整缓存。
/// 若 bundle 中找不到资源（常见于未 `flutter clean` 全量重装、或 APK 未打入 mp3），
/// 则清空插件缓存后回退 [setAsset]（与旧逻辑一致，便于对照日志）。
Future<void> loadWordClipIntoPlayer(
  AudioPlayer player,
  String assetPath, {
  AssetBundle? bundle,
}) async {
  final b = bundle ?? rootBundle;
  try {
    final data = await b.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (bytes.isEmpty) {
      throw StateError('empty asset');
    }
    final tmpDir = Directory.systemTemp;
    if (!tmpDir.existsSync()) {
      tmpDir.createSync(recursive: true);
    }
    final segs = assetPath.split('/');
    final short =
        segs.length >= 2 ? '${segs[segs.length - 2]}_${segs.last}' : '${assetPath.hashCode}.mp3';
    final safe = short.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final file = File('${tmpDir.path}/lj_sw_$safe');
    final raf = file.openSync(mode: FileMode.write);
    try {
      raf.setPositionSync(0);
      raf.writeFromSync(bytes);
      raf.truncateSync(bytes.length);
      raf.flushSync();
    } finally {
      raf.closeSync();
    }
    await player.setFilePath(file.path);
  } catch (_) {
    await AudioPlayer.clearAssetCache();
    await player.setAsset(assetPath);
  }
}
