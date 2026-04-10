import 'dart:async';
import 'dart:math' as math;

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

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play(String kind) async {
    final okey = _okey;
    if (okey.isEmpty) return;
    final path = kind == 'lesson'
        ? 'assets/audio/lesson/$okey.mp3'
        : 'assets/audio/word/$okey.mp3';
    setState(() {
      _busy = true;
      _panel = true;
    });
    try {
      await _player.setAsset(path);
      await _player.setSpeed(1);
      await _player.play();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '无法加载音频（$e）。若尚未下载资源，请在项目目录执行：dart run tool/fetch_audio.dart',
          ),
        ),
      );
      setState(() => _panel = false);
    } finally {
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
