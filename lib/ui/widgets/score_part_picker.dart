import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../models/midi_score_part.dart';

enum ScorePartPickerAction { apply, setSongDefault, setGlobalDefault }

class ScorePartPickerResult {
  final ScorePartPickerAction action;
  final Set<String> partIds;

  factory ScorePartPickerResult({
    required ScorePartPickerAction action,
    required Set<String> partIds,
  }) => ScorePartPickerResult._(
    action: action,
    partIds: Set<String>.unmodifiable(Set<String>.of(partIds)),
  );

  const ScorePartPickerResult._({required this.action, required this.partIds});
}

Future<ScorePartPickerResult?> showScorePartPicker(
  BuildContext context, {
  required MidiScoreCatalog catalog,
  required Set<String> selectedPartIds,
  required MidiSelectionOrigin origin,
  required Set<MidiNotationWarning> warnings,
  String? originLabelOverride,
}) {
  final selectedPartIdsSnapshot = Set<String>.unmodifiable(
    Set<String>.of(selectedPartIds),
  );
  final warningsSnapshot = Set<MidiNotationWarning>.unmodifiable(
    Set<MidiNotationWarning>.of(warnings),
  );
  return showCupertinoModalPopup<ScorePartPickerResult>(
    context: context,
    builder: (context) => _ScorePartPickerSheet(
      catalog: catalog,
      selectedPartIds: selectedPartIdsSnapshot,
      origin: origin,
      warnings: warningsSnapshot,
      originLabelOverride: originLabelOverride,
    ),
  );
}

class _ScorePartPickerSheet extends StatefulWidget {
  final MidiScoreCatalog catalog;
  final Set<String> selectedPartIds;
  final MidiSelectionOrigin origin;
  final Set<MidiNotationWarning> warnings;
  final String? originLabelOverride;

  const _ScorePartPickerSheet({
    required this.catalog,
    required this.selectedPartIds,
    required this.origin,
    required this.warnings,
    required this.originLabelOverride,
  });

  @override
  State<_ScorePartPickerSheet> createState() => _ScorePartPickerSheetState();
}

class _ScorePartPickerSheetState extends State<_ScorePartPickerSheet> {
  static const _paper = Color(0xFFF8F0DC);
  static const _paperRaised = Color(0xFFE9DDC6);
  static const _ink = Color(0xFF2A2118);
  static const _mutedInk = Color(0xFF5F4A35);
  static const _accent = Color(0xFFA2773F);
  static const _actionBar = Color(0xFF403640);
  static const _actionForeground = Color(0xFFF2DEAA);

  late final Set<String> _availablePartIds;
  late Set<String> _selectedPartIds;

  @override
  void initState() {
    super.initState();
    _availablePartIds = {
      for (final part in widget.catalog.parts)
        if (part.noteCount > 0) part.id,
    };
    _selectedPartIds = Set<String>.of(
      widget.selectedPartIds.where(_availablePartIds.contains),
    );
  }

  bool get _hasSelection => _selectedPartIds.isNotEmpty;

  void _togglePart(MidiScorePart part) {
    if (part.noteCount <= 0) return;
    setState(() {
      if (!_selectedPartIds.remove(part.id)) {
        _selectedPartIds.add(part.id);
      }
    });
  }

  void _selectAll() {
    setState(() => _selectedPartIds = Set<String>.of(_availablePartIds));
  }

  void _clear() {
    if (!_hasSelection) return;
    setState(_selectedPartIds.clear);
  }

  void _complete(ScorePartPickerAction action) {
    if (!_hasSelection) return;
    Navigator.of(
      context,
    ).pop(ScorePartPickerResult(action: action, partIds: _selectedPartIds));
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final sheetHeight = math.min(mediaQuery.size.height * 0.92, 720.0);
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: double.infinity,
        height: sheetHeight,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: ColoredBox(
            color: _paper,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildScrollableContent()),
                  _buildActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _paper,
        border: Border(bottom: BorderSide(color: Color(0x33715B41))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '选择显示声部',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.originLabelOverride ?? _originLabel(widget.origin),
                    style: const TextStyle(
                      color: _mutedInk,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _HeaderButton(label: '全选', onPressed: _selectAll),
            const SizedBox(width: 4),
            _HeaderButton(
              label: '清除',
              onPressed: _hasSelection ? _clear : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollableContent() {
    return ListView(
      key: const Key('score-part-list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        if (!_hasSelection) ...[
          const _SelectionRequiredMessage(),
          const SizedBox(height: 10),
        ],
        if (widget.warnings.isNotEmpty) ...[
          const Text(
            '显示提示',
            style: TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final warning in MidiNotationWarning.values)
            if (widget.warnings.contains(warning))
              _WarningRow(message: _warningLabel(warning)),
          const SizedBox(height: 8),
        ],
        for (final part in widget.catalog.parts) ...[
          _PartTile(
            part: part,
            selected: _selectedPartIds.contains(part.id),
            enabled: part.noteCount > 0,
            onPressed: () => _togglePart(part),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildActions() {
    final apply = _hasSelection
        ? () => _complete(ScorePartPickerAction.apply)
        : null;
    final setSongDefault = _hasSelection
        ? () => _complete(ScorePartPickerAction.setSongDefault)
        : null;
    final setGlobalDefault = _hasSelection
        ? () => _complete(ScorePartPickerAction.setGlobalDefault)
        : null;
    return ColoredBox(
      color: _actionBar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: _ActionButton(
                key: const Key('score-part-apply'),
                label: '应用',
                onPressed: apply,
                primary: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                key: const Key('score-part-song-default'),
                label: '设为本曲默认',
                onPressed: setSongDefault,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                key: const Key('score-part-global-default'),
                label: '设为全局默认',
                onPressed: setGlobalDefault,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _HeaderButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: onPressed == null
              ? _ScorePartPickerSheetState._mutedInk.withValues(alpha: 0.45)
              : _ScorePartPickerSheetState._accent,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SelectionRequiredMessage extends StatelessWidget {
  const _SelectionRequiredMessage();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: _ScorePartPickerSheetState._paperRaised,
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          '至少选择一个有音符声部',
          style: TextStyle(
            color: _ScorePartPickerSheetState._mutedInk,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _WarningRow extends StatelessWidget {
  final String message;

  const _WarningRow({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 15,
              color: _ScorePartPickerSheetState._accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _ScorePartPickerSheetState._mutedInk,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PartTile extends StatelessWidget {
  final MidiScorePart part;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  const _PartTile({
    required this.part,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final kind = _kindLabel(part.kind);
    final staff = _staffLabel(part.staffMode);
    final state = selected ? '已选择' : '未选择';
    return Semantics(
      key: Key('score-part-${part.id}'),
      label: '${part.label}，$kind，${part.noteCount} 个音符，$staff，$state',
      button: true,
      enabled: enabled,
      onTap: enabled ? onPressed : null,
      child: ExcludeSemantics(
        child: CupertinoButton(
          minimumSize: const Size(double.infinity, 58),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          color: selected
              ? _ScorePartPickerSheetState._paperRaised
              : CupertinoColors.white.withValues(alpha: 0.42),
          disabledColor: CupertinoColors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          onPressed: enabled ? onPressed : null,
          child: Row(
            children: [
              Icon(
                selected
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.circle,
                color: enabled
                    ? _ScorePartPickerSheetState._accent
                    : _ScorePartPickerSheetState._mutedInk.withValues(
                        alpha: 0.38,
                      ),
                size: 23,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      part.label,
                      style: TextStyle(
                        color: enabled
                            ? _ScorePartPickerSheetState._ink
                            : _ScorePartPickerSheetState._mutedInk.withValues(
                                alpha: 0.5,
                              ),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$kind · ${part.noteCount} 个音符 · $staff',
                      style: TextStyle(
                        color: _ScorePartPickerSheetState._mutedInk.withValues(
                          alpha: enabled ? 1 : 0.5,
                        ),
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  const _ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: CupertinoButton(
          minimumSize: const Size(double.infinity, 46),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 11),
          color: primary && enabled
              ? _ScorePartPickerSheetState._paper
              : CupertinoColors.transparent,
          disabledColor: CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(12),
          onPressed: onPressed,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: enabled
                    ? (primary
                          ? _ScorePartPickerSheetState._actionBar
                          : _ScorePartPickerSheetState._actionForeground)
                    : _ScorePartPickerSheetState._actionForeground.withValues(
                        alpha: 0.36,
                      ),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _originLabel(MidiSelectionOrigin origin) => switch (origin) {
  MidiSelectionOrigin.songDefault => '使用本曲默认',
  MidiSelectionOrigin.globalDefault => '使用全局默认',
  MidiSelectionOrigin.automaticPiano => '自动选择钢琴',
  MidiSelectionOrigin.automaticEnsemble => '自动选择非打击乐声部',
  MidiSelectionOrigin.percussionFallback => '仅打击乐回退',
};

String _kindLabel(MidiPartKind kind) => switch (kind) {
  MidiPartKind.piano => '钢琴',
  MidiPartKind.strings => '弦乐',
  MidiPartKind.woodwind => '木管',
  MidiPartKind.brass => '铜管',
  MidiPartKind.guitar => '吉他',
  MidiPartKind.bass => '贝斯',
  MidiPartKind.percussion => '打击乐',
  MidiPartKind.voice => '人声',
  MidiPartKind.synth => '合成器',
  MidiPartKind.other => '其他',
};

String _staffLabel(MidiStaffMode staffMode) => switch (staffMode) {
  MidiStaffMode.grandStaff => '大谱表（高音与低音谱表）',
  MidiStaffMode.singleStaff => '单谱表',
  MidiStaffMode.percussionStaff => '打击乐谱表',
};

String _warningLabel(MidiNotationWarning warning) => switch (warning) {
  MidiNotationWarning.rhythmQuantized => '部分节奏已对齐到可显示的记谱网格，时值可能有轻微调整。',
  MidiNotationWarning.unknownInstrument => '部分轨道名或乐器无法识别，已按独立声部使用通用单谱表显示。',
  MidiNotationWarning.irregularTimeSignature => '拍号变化不在标准小节边界，已截断当前小节以保持时间轴对齐。',
  MidiNotationWarning.densePassage => '部分段落声部过密，显示谱已简化为最多四个声部。',
};
