import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// 课程详情外壳：AppBar 课文/单词朗读 + 底部播放条（与 Ionic `item-detail` 行为对应）。
class LessonDetailShell extends StatefulWidget {
  const LessonDetailShell({
    super.key,
    required this.item,
    required this.title,
    required this.body,
  });

  final Map<String, dynamic> item;
  final Widget title;
  final Widget body;

  @override
  State<LessonDetailShell> createState() => _LessonDetailShellState();
}

class _LessonDetailShellState extends State<LessonDetailShell> {
  final AudioPlayer _player = AudioPlayer();
  bool _panel = false;
  bool _busy = false;

  String get _okey => widget.item['okey'] as String? ?? '';

  void _lessonAudioLog(String msg) => debugPrint('[LessonAudio] $msg');

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play(String kind) async {
    final okey = _okey;
    _lessonAudioLog('_play start kind=$kind okey="$okey"');
    if (okey.isEmpty) {
      _lessonAudioLog('_play abort okey empty');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('本课缺少音频标识（okey），无法播放。请从课程列表进入课文页再试。'),
        ),
      );
      return;
    }
    final base = kind == 'lesson' ? 'assets/audio/lesson/' : 'assets/audio/word/';
    const exts = <String>['.mp3', '.wav'];
    _lessonAudioLog('_play try $base$okey.(mp3|wav)');
    setState(() {
      _busy = true;
      _panel = true;
    });
    try {
      if (!kIsWeb) {
        try {
          final session = await AudioSession.instance;
          await session.configure(const AudioSessionConfiguration.music());
          await session.setActive(true);
          _lessonAudioLog('_play AudioSession music+active ok');
        } catch (e, st) {
          _lessonAudioLog('AudioSession: $e\n$st');
        }
      }
      await _player.stop();
      _lessonAudioLog('_play after stop()');
      Object? lastErr;
      var played = '';
      for (final ext in exts) {
        final path = '$base$okey$ext';
        try {
          await _player.setAsset(path);
          played = path;
          break;
        } catch (e) {
          lastErr = e;
        }
      }
      if (played.isEmpty) {
        throw lastErr ?? Exception('未找到 $base$okey 的 mp3 或 wav');
      }
      _lessonAudioLog(
        '_play setAsset ok path=$played duration=${_player.duration} '
        'processing=${_player.processingState}',
      );
      await _player.setSpeed(1);
      await _player.seek(Duration.zero);
      await _player.play();
      _lessonAudioLog(
        '_play play() returned playing=${_player.playing} processing=${_player.processingState}',
      );
    } catch (e) {
      _lessonAudioLog('_play EXCEPTION: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '无法播放内置音频（与系统「文字转语音」无关）。\n$e\n'
            '可：dart run tool/fetch_audio.dart 拉取 MP3，'
            '或 python tool/synth_audio_piper.py 生成本机 Piper WAV。',
          ),
        ),
      );
      setState(() => _panel = false);
    } finally {
      _lessonAudioLog('_play finally busy->false');
      if (mounted) setState(() => _busy = false);
    }
  }

  void _closePanel() {
    unawaited(_player.stop());
    setState(() => _panel = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: widget.title,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: '课文朗读',
            onPressed: _busy ? null : () => _play('lesson'),
          ),
          IconButton(
            icon: const Icon(Icons.audiotrack),
            tooltip: '单词朗读',
            onPressed: _busy ? null : () => _play('word'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: widget.body),
          if (_panel) _LessonAudioDock(player: _player, onClose: _closePanel),
        ],
      ),
    );
  }
}

class _LessonAudioDock extends StatelessWidget {
  const _LessonAudioDock({
    required this.player,
    required this.onClose,
  });

  final AudioPlayer player;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: cs.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                    tooltip: '关闭',
                  ),
                  Expanded(
                    child: StreamBuilder<Duration>(
                      stream: player.positionStream,
                      builder: (context, posSnap) {
                        final pos = posSnap.data ?? Duration.zero;
                        return StreamBuilder<Duration?>(
                          stream: player.durationStream,
                          builder: (context, durSnap) {
                            final dur = durSnap.data ?? Duration.zero;
                            final maxMs = dur.inMilliseconds > 0
                                ? dur.inMilliseconds.toDouble()
                                : 1.0;
                            final v = pos.inMilliseconds
                                .clamp(0, dur.inMilliseconds)
                                .toDouble();
                            return Slider(
                              value: v,
                              max: maxMs,
                              onChanged: (x) {
                                player.seek(
                                  Duration(milliseconds: x.round()),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () async {
                      final p = player.position;
                      await player.seek(
                        Duration(
                          milliseconds: math.max(
                            0,
                            p.inMilliseconds - 2000,
                          ),
                        ),
                      );
                    },
                    child: const Text('短退'),
                  ),
                  StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    builder: (context, snap) {
                      final playing = snap.data?.playing ?? false;
                      return IconButton(
                        icon: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                        ),
                        iconSize: 40,
                        onPressed: () {
                          if (playing) {
                            player.pause();
                          } else {
                            player.play();
                          }
                        },
                      );
                    },
                  ),
                  TextButton(
                    onPressed: () => player.setSpeed(0.8),
                    child: const Text('慢速'),
                  ),
                  TextButton(
                    onPressed: () => player.setSpeed(1),
                    child: const Text('常速'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
