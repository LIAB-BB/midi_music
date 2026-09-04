import 'dart:async';

import 'package:core_midi_input/core_midi_input.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/follow_mode_controller.dart';
import 'core/k478_midi_follow_session.dart';
import 'core/k478_player.dart';
import 'core/midi_parser.dart';

const _midiAsset =
    'packages/k478_practice/assets/midi/mozart_k478_piano_quartet.mid';
const _scoreAssetPrefix = 'assets/scores/mozart_k478_piano_part/page';
const _scorePageCount = 21;

class K478PracticeApp extends StatelessWidget {
  /// 仅用于 widget 验证 App 内部的 Dynamic Type 布局；生产调用保持 null。
  final TextScaler? textScalerOverride;

  const K478PracticeApp({super.key, this.textScalerOverride});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => K478PlayerController(),
      child: CupertinoApp(
        title: 'K.478 排练',
        debugShowCheckedModeBanner: false,
        theme: const CupertinoThemeData(
          brightness: Brightness.dark,
          primaryColor: _Palette.gold,
          scaffoldBackgroundColor: _Palette.background,
          barBackgroundColor: Color(0xE6090909),
        ),
        builder: (context, child) {
          final override = textScalerOverride;
          if (override == null || child == null) {
            return child ?? const SizedBox.shrink();
          }
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: override),
            child: child,
          );
        },
        home: const _HomePage(),
      ),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  final _parser = MidiFileParser();
  var _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    if (mounted) setState(() => _loading = true);
    try {
      final raw = await rootBundle.load(_midiAsset);
      final song = _parser.parseBytes(
        raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
        fileName: 'mozart_k478_piano_quartet.mid',
      );
      if (!mounted) return;
      final player = context.read<K478PlayerController>();
      await player.loadSong(song);
      await player.prepareSoundfont();
      _loadError = null;
    } catch (error) {
      _loadError = '内置 MIDI 载入失败：$error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        border: null,
        middle: const Text('K.478 排练'),
        trailing: Semantics(
          label: '第三方通知',
          button: true,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => unawaited(
              Navigator.of(context).push(
                CupertinoPageRoute<void>(builder: (_) => const _NoticesPage()),
              ),
            ),
            child: const Icon(CupertinoIcons.info_circle),
          ),
        ),
      ),
      child: _Backdrop(
        child: SafeArea(
          bottom: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Consumer<K478PlayerController>(
                  builder: (context, player, _) => _HomeCard(
                    loading: _loading,
                    loadError: _loadError,
                    player: player,
                    onRetry: () => unawaited(_bootstrap()),
                    onOpenPractice: () => unawaited(
                      Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => const _PracticePage(),
                        ),
                      ),
                    ),
                    onOpenScore: () => unawaited(
                      Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => const _ScorePage(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final bool loading;
  final String? loadError;
  final K478PlayerController player;
  final VoidCallback onRetry;
  final VoidCallback onOpenPractice;
  final VoidCallback onOpenScore;

  const _HomeCard({
    required this.loading,
    required this.loadError,
    required this.player,
    required this.onRetry,
    required this.onOpenPractice,
    required this.onOpenScore,
  });

  @override
  Widget build(BuildContext context) {
    final ready = player.song != null && player.isSoundfontReady;
    final soundfontLabel = switch (player.soundfontState) {
      SoundfontState.idle || SoundfontState.loading => '正在准备离线弦乐音色',
      SoundfontState.ready => '离线弦乐音色已就绪',
      SoundfontState.failed => player.soundfontError ?? '弦乐音色不可用',
    };
    return _Panel(
      highlighted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('iOS · CoreMIDI · TESTFLIGHT CANDIDATE'),
          const SizedBox(height: 16),
          const Text('钢琴四重奏\nK.478', style: _displayStyle),
          const SizedBox(height: 10),
          const Text(
            '莫扎特 · 钢琴右手、左手与弦乐分轨\n首轮只验证一首内置曲目与 CoreMIDI 跟随。',
            style: _mutedStyle,
          ),
          const SizedBox(height: 22),
          _StatusRow(
            icon: player.soundfontState == SoundfontState.ready
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.waveform,
            label: soundfontLabel,
            healthy: player.soundfontState == SoundfontState.ready,
          ),
          const SizedBox(height: 9),
          const _StatusRow(
            icon: CupertinoIcons.music_note,
            label: '钢琴由外接电子琴发声；App 只播放弦乐伴奏。',
            healthy: true,
          ),
          if (loadError != null) ...[
            const SizedBox(height: 16),
            _ErrorBox(message: loadError!),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              onPressed: loading ? null : (ready ? onOpenPractice : onRetry),
              child: loading
                  ? const CupertinoActivityIndicator(
                      color: CupertinoColors.black,
                    )
                  : Text(ready ? '进入 MIDI 排练' : '重试准备离线音色'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              onPressed: onOpenScore,
              child: const Text('查看钢琴声部版面'),
            ),
          ),
          const Text(
            '版面为内置 PDF 预渲染页，用于排练对照；尚不是可编辑 MusicXML。',
            style: _smallMutedStyle,
          ),
        ],
      ),
    );
  }
}

class _PracticePage extends StatefulWidget {
  const _PracticePage();

  @override
  State<_PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<_PracticePage> {
  K478MidiFollowSession? _followSession;
  K478MidiFollowSession? _startingFollowSession;
  StreamSubscription<MidiInputState>? _stateSubscription;
  MidiInputState _inputState = const MidiInputState();
  String? _followError;
  var _isStartingFollow = false;

  @override
  void dispose() {
    unawaited(_disposeFollowSession());
    super.dispose();
  }

  Future<void> _toggleFollow(K478PlayerController player) async {
    if (_followSession != null || _startingFollowSession != null) {
      await _disposeFollowSession();
      if (mounted) setState(() {});
      return;
    }
    if (_isStartingFollow) return;
    if (!player.isSoundfontReady) {
      await _showDialog('弦乐音色尚未准备好', '请回到首页重试准备离线音色。');
      return;
    }

    setState(() {
      _isStartingFollow = true;
      _inputState = const MidiInputState();
      _followError = null;
    });
    final input = IosMidiInput();
    late final K478MidiFollowSession session;
    final stateSubscription = input.states.listen((state) {
      if (mounted && _ownsSession(session)) {
        setState(() => _inputState = state);
      }
    });
    _stateSubscription = stateSubscription;
    session = K478MidiFollowSession(
      player: player,
      performerTracks: player.performerTracks,
      input: input,
      config: const FollowModeConfig(),
    );
    _startingFollowSession = session;
    session.onStateChanged = (_) {
      if (mounted && _ownsSession(session)) setState(() {});
    };
    session.onTerminated = (terminatedSession, error) {
      if (!mounted || !_ownsSession(terminatedSession)) return;
      unawaited(_handleTerminatedSession(terminatedSession, error));
    };
    try {
      await session.start();
      if (!mounted ||
          !session.isActive ||
          !identical(_startingFollowSession, session)) {
        await session.dispose();
        await _cancelStateSubscription(stateSubscription);
        if (mounted) {
          setState(() => _followError = 'MIDI 输入在启动过程中已中断；请检查连接后重试。');
        }
        return;
      }
      setState(() {
        _followSession = session;
        _startingFollowSession = null;
        _followError = null;
      });
    } catch (error) {
      await session.dispose();
      await _cancelStateSubscription(stateSubscription);
      if (mounted) setState(() => _followError = '$error');
    } finally {
      if (mounted) {
        setState(() {
          if (identical(_startingFollowSession, session)) {
            _startingFollowSession = null;
          }
          _isStartingFollow = false;
        });
      } else if (identical(_startingFollowSession, session)) {
        _startingFollowSession = null;
      }
    }
  }

  Future<void> _disposeFollowSession() async {
    final activeSession = _followSession;
    final startingSession = _startingFollowSession;
    _followSession = null;
    _startingFollowSession = null;
    final stateSubscription = _stateSubscription;
    _stateSubscription = null;
    await stateSubscription?.cancel();
    await activeSession?.dispose();
    if (startingSession != null && !identical(startingSession, activeSession)) {
      await startingSession.dispose();
    }
  }

  bool _ownsSession(K478MidiFollowSession session) =>
      identical(_followSession, session) ||
      identical(_startingFollowSession, session);

  Future<void> _cancelStateSubscription(
    StreamSubscription<MidiInputState> subscription,
  ) async {
    await subscription.cancel();
    if (identical(_stateSubscription, subscription)) {
      _stateSubscription = null;
    }
  }

  Future<void> _handleTerminatedSession(
    K478MidiFollowSession session,
    Object error,
  ) async {
    if (!_ownsSession(session)) return;
    if (identical(_followSession, session)) _followSession = null;
    if (identical(_startingFollowSession, session)) {
      _startingFollowSession = null;
    }
    final stateSubscription = _stateSubscription;
    _stateSubscription = null;
    await stateSubscription?.cancel();
    if (mounted) {
      setState(() => _followError = 'MIDI 输入已中断：$error。请重新开始跟随。');
    }
  }

  Future<void> _showDialog(String title, String message) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        border: null,
        middle: const Text('K.478 演奏台'),
        trailing: Semantics(
          label: '查看乐谱',
          button: true,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => unawaited(
              Navigator.of(context).push(
                CupertinoPageRoute<void>(builder: (_) => const _ScorePage()),
              ),
            ),
            child: const Text('乐谱'),
          ),
        ),
      ),
      child: _Backdrop(
        child: SafeArea(
          bottom: false,
          child: Consumer<K478PlayerController>(
            builder: (context, player, _) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                _transportPanel(player),
                const SizedBox(height: 14),
                _usbPanel(player),
                const SizedBox(height: 14),
                _stringsPanel(player),
                const SizedBox(height: 14),
                _speedPanel(player),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _transportPanel(K478PlayerController player) {
    final followActive = _followSession?.isActive ?? false;
    final transportLocked = isFollowTransportLocked(
      isStartingFollow: _isStartingFollow,
      sessionActive: followActive,
    );
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('演奏与跟随'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(_time(player.currentTime), style: _timeStyle),
              ),
              Text(
                '/ ${_time(player.totalDuration)} · ${player.currentBpm.toStringAsFixed(0)} BPM',
                style: _smallMutedStyle,
              ),
            ],
          ),
          Semantics(
            label: '播放位置',
            child: CupertinoSlider(
              value: player.progress,
              onChanged: transportLocked || player.totalDuration == 0
                  ? null
                  : (value) =>
                        unawaited(player.seekTo(value * player.totalDuration)),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundControl(
                icon: CupertinoIcons.stop_fill,
                onPressed: transportLocked
                    ? null
                    : () => unawaited(player.stop()),
                semanticLabel: '停止伴奏',
              ),
              _RoundControl(
                icon: player.isPlaying
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill,
                emphasized: true,
                onPressed: transportLocked
                    ? null
                    : () => unawaited(
                        player.isPlaying ? player.pause() : player.play(),
                      ),
                semanticLabel: player.isPlaying ? '暂停伴奏' : '播放伴奏',
              ),
              _RoundControl(
                icon: CupertinoIcons.backward_end_fill,
                onPressed: transportLocked
                    ? null
                    : () => unawaited(player.seekTo(0)),
                semanticLabel: '回到开头',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _usbPanel(K478PlayerController player) {
    final session = _followSession ?? _startingFollowSession;
    final connection = midiConnectionPresentation(
      sessionActive: session?.isActive ?? false,
      isConnected: _inputState.isConnected,
      primaryDeviceName: _inputState.primaryDeviceName,
      followState: session?.state ?? FollowModeState.idle,
    );
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('COREMIDI 输入'),
          const SizedBox(height: 12),
          _StatusRow(
            icon: connection.healthy
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.xmark_circle,
            label: connection.label,
            healthy: connection.healthy,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              onPressed: _isStartingFollow
                  ? null
                  : () => unawaited(_toggleFollow(player)),
              child: Text(
                _isStartingFollow
                    ? '正在启动 MIDI 跟随'
                    : session == null
                    ? '开始 MIDI 跟随'
                    : '停止 MIDI 跟随',
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '首轮验收使用直连 USB 电子琴；首个正确起拍才启动弦乐。App 不接收或播放钢琴声部音频。',
            style: _smallMutedStyle,
          ),
          if (_followError != null) ...[
            const SizedBox(height: 12),
            _ErrorBox(message: _followError!),
          ],
        ],
      ),
    );
  }

  Widget _stringsPanel(K478PlayerController player) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('弦乐伴奏'),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('小提琴 / 中提琴声部 / 大提琴'),
                    SizedBox(height: 3),
                    Text(
                      '中提琴声部当前暂用小提琴音色；钢琴两轨永久留给电子琴。',
                      style: _smallMutedStyle,
                    ),
                  ],
                ),
              ),
              Semantics(
                label: '弦乐伴奏开关',
                child: CupertinoSwitch(
                  value: player.stringsEnabled,
                  onChanged: player.setStringsEnabled,
                ),
              ),
            ],
          ),
          Semantics(
            label: '弦乐伴奏音量',
            child: CupertinoSlider(
              value: player.stringsVolume,
              onChanged: player.setStringsVolume,
            ),
          ),
          Text(
            '伴奏音量 ${(player.stringsVolume * 100).round()}%',
            style: _smallMutedStyle,
          ),
        ],
      ),
    );
  }

  Widget _speedPanel(K478PlayerController player) {
    const speeds = [0.5, 0.75, 1.0, 1.25];
    final followActive = _followSession?.isActive ?? false;
    final transportLocked = isFollowTransportLocked(
      isStartingFollow: _isStartingFollow,
      sessionActive: followActive,
    );
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('速度'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: speeds
                .map((speed) {
                  final selected = (player.playbackSpeed - speed).abs() < 0.01;
                  return Semantics(
                    button: true,
                    label: '速度 ${speed.toStringAsFixed(speed == 1 ? 0 : 2)} 倍',
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      color: selected ? _Palette.gold : _Palette.raised,
                      onPressed: transportLocked
                          ? null
                          : () => player.setSpeed(speed),
                      child: Text(
                        '${speed.toStringAsFixed(speed == 1 ? 0 : 2)}×',
                        style: TextStyle(
                          color: selected
                              ? CupertinoColors.black
                              : _Palette.primary,
                        ),
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _ScorePage extends StatefulWidget {
  const _ScorePage();

  @override
  State<_ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends State<_ScorePage> {
  final _controller = PageController();
  var _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        border: null,
        middle: Text('钢琴声部 · ${_currentPage + 1}/$_scorePageCount'),
      ),
      child: ColoredBox(
        color: const Color(0xFFF2EEE5),
        child: SafeArea(
          child: Semantics(
            label: '第${_currentPage + 1}页，共$_scorePageCount页',
            child: PageView.builder(
              controller: _controller,
              itemCount: _scorePageCount,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, index) => InteractiveViewer(
                minScale: 0.8,
                maxScale: 3,
                child: Center(
                  child: Image.asset(
                    '$_scoreAssetPrefix-${(index + 1).toString().padLeft(2, '0')}.png',
                    package: 'k478_practice',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticesPage extends StatelessWidget {
  const _NoticesPage();

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        border: null,
        middle: Text('第三方通知'),
      ),
      child: SafeArea(
        child: FutureBuilder<String>(
          future: rootBundle.loadString(
            'packages/k478_practice/assets/legal/third_party_notices.txt',
          ),
          builder: (context, snapshot) {
            final text = snapshot.data;
            if (text == null) {
              return const Center(child: CupertinoActivityIndicator());
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.48,
                  color: _Palette.primary,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;
  final String semanticLabel;

  const _RoundControl({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Container(
          width: emphasized ? 58 : 46,
          height: emphasized ? 58 : 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: emphasized ? _Palette.gold : _Palette.raised,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: emphasized ? CupertinoColors.black : _Palette.primary,
            size: emphasized ? 24 : 18,
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool healthy;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.healthy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: healthy ? _Palette.green : _Palette.gold),
        const SizedBox(width: 9),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 13, height: 1.4)),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF3D1F1B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message, style: const TextStyle(color: Color(0xFFFFC9BF))),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  final Widget child;

  const _Backdrop({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF18110D), _Palette.background, Color(0xFF050505)],
        ),
      ),
      child: child,
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final bool highlighted;

  const _Panel({required this.child, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFF211A14) : _Palette.panel,
        border: Border.all(
          color: highlighted
              ? const Color(0x55D3B06D)
              : const Color(0x33D3B06D),
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String label;

  const _Eyebrow(this.label);

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: _Palette.gold,
    ),
  );
}

String _time(double seconds) {
  final value = seconds.clamp(0, 1 << 30).floor();
  return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
}

String _followStateLabel(FollowModeState state) => switch (state) {
  FollowModeState.idle => '未开始',
  FollowModeState.following => '跟随中',
  FollowModeState.waitingForOnset => '等待下一起拍',
};

/// USB 状态面板的唯一展示规则；会话存在不代表设备仍然连接。
({String label, bool healthy}) midiConnectionPresentation({
  required bool sessionActive,
  required bool isConnected,
  String? primaryDeviceName,
  required FollowModeState followState,
}) {
  if (!sessionActive) {
    return (label: '尚未开始 MIDI 跟随', healthy: false);
  }
  if (!isConnected) {
    return (label: 'CoreMIDI · 未检测到设备', healthy: false);
  }
  return (
    label:
        '${primaryDeviceName ?? 'CoreMIDI 设备'} · ${_followStateLabel(followState)}',
    healthy: true,
  );
}

/// 启动会话尚未完成时，也必须锁住手动 transport，避免抢先播放伴奏。
bool isFollowTransportLocked({
  required bool isStartingFollow,
  required bool sessionActive,
}) => isStartingFollow || sessionActive;

class _Palette {
  static const background = Color(0xFF060606);
  static const panel = Color(0xFF161311);
  static const raised = Color(0xFF29231E);
  static const gold = Color(0xFFD3B06D);
  static const green = Color(0xFF73B693);
  static const primary = Color(0xFFF6F0E6);
  static const muted = Color(0xFFB5A58A);
  static const subtle = Color(0xFF8F8578);
}

const _displayStyle = TextStyle(
  fontSize: 38,
  height: 1.05,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.2,
  color: _Palette.primary,
  fontFamily: 'Georgia',
);

const _timeStyle = TextStyle(
  fontSize: 30,
  fontWeight: FontWeight.w600,
  color: _Palette.primary,
);

const _mutedStyle = TextStyle(fontSize: 14, height: 1.5, color: _Palette.muted);
const _smallMutedStyle = TextStyle(
  fontSize: 12,
  height: 1.45,
  color: _Palette.subtle,
);
