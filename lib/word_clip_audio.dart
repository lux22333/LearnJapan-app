import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'word_clip_audio_io.dart' if (dart.library.html) 'word_clip_audio_stub.dart' as impl;

/// 背词 / 单词详情：加载 `assets/single_words/...` 到 [AudioPlayer]。
Future<void> loadWordClipIntoPlayer(
  AudioPlayer player,
  String assetPath, {
  AssetBundle? bundle,
}) =>
    impl.loadWordClipIntoPlayer(player, assetPath, bundle: bundle);
