import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'camera_providers.dart';
import 'tile_recognizer.dart';

/// カメラ認識（Qwen API）の設定画面
class CameraSettingsScreen extends ConsumerStatefulWidget {
  const CameraSettingsScreen({super.key});

  @override
  ConsumerState<CameraSettingsScreen> createState() => _CameraSettingsScreenState();
}

class _CameraSettingsScreenState extends ConsumerState<CameraSettingsScreen> {
  late final TextEditingController _key;
  late final TextEditingController _model;
  late String _endpoint;
  bool _showKey = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(cameraSettingsProvider);
    _key = TextEditingController(text: s.apiKey);
    _model = TextEditingController(text: s.model);
    _endpoint = s.endpoint;
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(cameraSettingsProvider.notifier).save(CameraSettings(
          apiKey: _key.text.trim(),
          endpoint: _endpoint,
          model: _model.text.trim().isEmpty ? CameraSettings.defaultModel : _model.text.trim(),
        ));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('カメラ認識の設定を保存しました')));
    Navigator.of(context).pop();
  }

  Future<void> _deleteKey() async {
    await ref.read(cameraSettingsProvider.notifier).save(const CameraSettings());
    if (!mounted) return;
    setState(() {
      _key.clear();
      _model.text = CameraSettings.defaultModel;
      _endpoint = CameraSettings.intlEndpoint;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('API キーを削除しました')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(title, style: theme.textTheme.titleMedium),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('カメラ認識の設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '手牌の写真を Qwen（アリババクラウドの、画像を理解する AI）に送って、牌を読み取ります。'
            '使うには Alibaba Cloud Model Studio（DashScope）の API キーが必要です。',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '・撮った写真は、読み取りのために Qwen（アリババクラウド）に送られます。\n'
                '・API の利用料がかかります（料金は Alibaba Cloud のアカウントに請求されます）。\n'
                '・API キーはこの端末の中にだけ保存されます。バックアップには入りません。'
                '他の人に端末を貸すときや、使わなくなったときは削除してください。\n'
                '・読み取り結果は間違えることがあります。入力後に必ず確認してください。\n'
                '・Web 版では、ブラウザの安全上の制限で接続できない場合があります。',
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer, fontSize: 13),
              ),
            ),
          ),
          section('API キー'),
          TextField(
            controller: _key,
            obscureText: !_showKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API キー',
              hintText: 'sk-...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _showKey ? '隠す' : '表示する',
                icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'API キーは Alibaba Cloud Model Studio のコンソールで作成できます（「API キー」の画面）。',
              style: small,
            ),
          ),
          section('接続先の地域'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: CameraSettings.intlEndpoint, label: Text('国際版')),
              ButtonSegment(value: CameraSettings.chinaEndpoint, label: Text('中国本土版')),
            ],
            selected: {_endpoint},
            onSelectionChanged: (v) => setState(() => _endpoint = v.first),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('API キーを作った地域に合わせてください（地域が違うとキーが使えません）。', style: small),
          ),
          section('モデル'),
          Wrap(
            spacing: 8,
            children: [
              for (final m in const ['qwen-vl-max', 'qwen-vl-plus'])
                ChoiceChip(
                  label: Text(m),
                  selected: _model.text.trim() == m,
                  onSelected: (_) => setState(() => _model.text = m),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _model,
            decoration: const InputDecoration(
              labelText: 'モデル名',
              helperText: 'qwen-vl-max は読み取りが正確、qwen-vl-plus は安くて速い。ほかのモデル名も入力できます',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('保存')),
          const SizedBox(height: 8),
          if (ref.watch(cameraSettingsProvider).isConfigured)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                foregroundColor: theme.colorScheme.error,
              ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('API キーを削除'),
              onPressed: _deleteKey,
            ),
        ],
      ),
    );
  }
}
