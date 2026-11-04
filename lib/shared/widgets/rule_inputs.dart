import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../features/session/domain/models.dart';

/// 点数の入力欄（よく使う値のボタン＋自由に入力できるテキストボックス）
///
/// [onChanged] には入力された数値を渡す（数字になっていなければ null）。
/// 入力チェックの結果は [errorText] で外から渡す。
class PointsInput extends StatefulWidget {
  final String label;
  final int initialValue;
  final List<int> presets;
  final String? errorText;
  final ValueChanged<int?> onChanged;

  const PointsInput({
    super.key,
    required this.label,
    required this.initialValue,
    required this.presets,
    required this.onChanged,
    this.errorText,
  });

  @override
  State<PointsInput> createState() => _PointsInputState();
}

class _PointsInputState extends State<PointsInput> {
  late final _controller = TextEditingController(text: '${widget.initialValue}');

  int? get _value => int.tryParse(_controller.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setPreset(int v) {
    setState(() => _controller.text = '$v');
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final p in widget.presets)
              ChoiceChip(
                label: Text(formatPoints(p)),
                selected: _value == p,
                onSelected: (_) => _setPreset(p),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: widget.label,
            suffixText: '点',
            helperText: '上のボタン以外の値も入力できます（100点単位）',
            errorText: widget.errorText,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) {
            setState(() {}); // ボタンの選択状態を更新
            widget.onChanged(_value);
          },
        ),
      ],
    );
  }
}

/// ウマの入力欄（よく使うウマのボタン＋1位〜4位のテキストボックス）
///
/// [onChanged] には4人分の値を渡す（数字になっていない欄は null）。
class UmaInput extends StatefulWidget {
  final List<int> initialValue;
  final String? errorText;
  final ValueChanged<List<int?>> onChanged;

  const UmaInput({
    super.key,
    required this.initialValue,
    required this.onChanged,
    this.errorText,
  });

  @override
  State<UmaInput> createState() => _UmaInputState();
}

class _UmaInputState extends State<UmaInput> {
  late final _controllers = [
    for (final v in widget.initialValue) TextEditingController(text: '$v')
  ];

  List<int?> get _values => [for (final c in _controllers) int.tryParse(c.text)];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _setPreset(List<int> uma) {
    setState(() {
      for (var i = 0; i < 4; i++) {
        _controllers[i].text = '${uma[i]}';
      }
    });
    widget.onChanged(uma);
  }

  bool _matches(List<int> uma) {
    final v = _values;
    for (var i = 0; i < 4; i++) {
      if (v[i] != uma[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final p in umaPresets)
              ChoiceChip(
                label: Text(p.$1),
                selected: _matches(p.$2),
                onSelected: (_) => _setPreset(p.$2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  key: ValueKey('uma-$i'),
                  controller: _controllers[i],
                  keyboardType:
                      const TextInputType.numberWithOptions(signed: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                  ],
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: '${i + 1}位',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) {
                    setState(() {});
                    widget.onChanged(_values);
                  },
                ),
              ),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            widget.errorText ?? '千点単位で入力します（例: 10-20 なら 1位+20・2位+10・3位-10・4位-20）。合計は0にしてください。',
            style: theme.textTheme.bodySmall?.copyWith(
                color: widget.errorText != null ? theme.colorScheme.error : null),
          ),
        ),
      ],
    );
  }
}
