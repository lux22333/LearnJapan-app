// ignore_for_file: avoid_unused_parameters

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

Future<void> loadWordClipIntoPlayer(
  AudioPlayer player,
  String assetPath, {
  AssetBundle? bundle,
}) async {
  await player.setAsset(assetPath);
}
