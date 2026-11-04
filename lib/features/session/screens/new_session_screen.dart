import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routes.dart';
import '../domain/models.dart';
import '../session_providers.dart';

/// 新規対局の作成画面
class NewSessionScreen extends ConsumerStatefulWidget {
  const NewSessionScreen({super.key});

  @override
  ConsumerState<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends ConsumerState<NewSessionScreen> {
  final _controllers = List.generate(
      4, (i) => TextEditingController(text: 'プレイヤー${i + 1}'));
  bool _tonpuu = false;
  bool _tobi = true;
  int _starting = 25000;
  int _return = 30000;
  int _umaIndex = 1;

  static const _umaOptions = [
    ('なし', [0, 0, 0, 0]),
    ('10-20', [20, 10, -10, -20]),
    ('10-30', [30, 10, -10, -30]),
    ('5-10', [10, 5, -5, -10]),
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _start() {
    final names = [
      for (var i = 0; i < 4; i++)
        _controllers[i].text.trim().isEmpty
            ? 'プレイヤー${i + 1}'
            : _controllers[i].text.trim()
    ];
    final settings = GameSettings(
      startingPoints: _starting,
      returnPoints: _return < _starting ? _starting : _return,
      uma: _umaOptions[_umaIndex].$2,
      tonpuu: _tonpuu,
      tobi: _tobi,
    );
    final id = ref.read(sessionsProvider.notifier).create(names, settings);
    Navigator.of(context).pushReplacement(dashboardRoute(id));
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );

  @override
  Widget build(BuildContext context) {
    const winds = ['東家（起家）', '南家', '西家', '北家'];
    return Scaffold(
      appBar: AppBar(title: const Text('新規対局')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('プレイヤー', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: _controllers[i],
                decoration: InputDecoration(
                  labelText: winds[i],
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('ルール', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('半荘戦')),
              ButtonSegment(value: true, label: Text('東風戦')),
            ],
            selected: {_tonpuu},
            onSelectionChanged: (v) => setState(() => _tonpuu = v.first),
          ),
          const SizedBox(height: 12),
          _label(context, '持ち点'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 25000, label: Text('25,000')),
              ButtonSegment(value: 30000, label: Text('30,000')),
            ],
            selected: {_starting},
            onSelectionChanged: (v) => setState(() => _starting = v.first),
          ),
          _label(context, '返し（オカの基準）'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 25000, label: Text('25,000')),
              ButtonSegment(value: 30000, label: Text('30,000')),
            ],
            selected: {_return},
            onSelectionChanged: (v) => setState(() => _return = v.first),
          ),
          _label(context, 'ウマ'),
          SegmentedButton<int>(
            segments: [
              for (var i = 0; i < _umaOptions.length; i++)
                ButtonSegment(value: i, label: Text(_umaOptions[i].$1)),
            ],
            selected: {_umaIndex},
            onSelectionChanged: (v) => setState(() => _umaIndex = v.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('トビあり（0点未満で終了）'),
            value: _tobi,
            onChanged: (v) => setState(() => _tobi = v),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _start, child: const Text('対局開始')),
        ],
      ),
    );
  }
}
