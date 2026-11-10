import 'package:flutter/material.dart';

import '../../core/l10n.dart';

/// 名前の比べ方をそろえる（大文字・小文字と、カタカナ・ひらがなの違いを無視する）
String _normalize(String s) {
  final b = StringBuffer();
  for (final r in s.trim().toLowerCase().runes) {
    // カタカナ（ァ〜ヶ）はひらがなにする
    b.writeCharCode(r >= 0x30A1 && r <= 0x30F6 ? r - 0x60 : r);
  }
  return b.toString();
}

/// 過去のプレイヤーの名前から、[query] を含むもの（部分一致）を選ぶ。
/// [names] は新しく使った順。前方一致を先に、その中は [names] の順に並べる。
/// [exclude]（ほかの欄に入っている名前）と、入力と同じ名前は出さない
List<String> matchPlayerNames(List<String> names, String query, {Set<String> exclude = const {}}) {
  final q = _normalize(query);
  final head = <String>[], rest = <String>[];
  for (final n in names) {
    if (exclude.contains(n) || n == query.trim()) continue;
    final k = _normalize(n);
    if (q.isEmpty || k.startsWith(q)) {
      head.add(n);
    } else if (k.contains(q)) {
      rest.add(n);
    }
  }
  return [...head, ...rest];
}

/// プレイヤーの名前の入力欄。欄を押す（または右の ▼ を押す）と、過去に入力した名前の一覧が開き、
/// 入力した文字を含む名前（部分一致）に絞り込んで選べる
class PlayerNameField extends StatefulWidget {
  final TextEditingController controller;

  /// 過去に使った名前（新しく使った順）
  final List<String> candidates;

  /// 一覧に出さない名前（ほかの欄に入っている名前など）
  final Set<String> exclude;
  final String? labelText;
  final String? hintText;
  final ValueChanged<String>? onChanged;

  /// 入力欄（TextField）に付けるキー
  final Key? fieldKey;

  const PlayerNameField({
    super.key,
    required this.controller,
    required this.candidates,
    this.exclude = const {},
    this.labelText,
    this.hintText,
    this.onChanged,
    this.fieldKey,
  });

  @override
  State<PlayerNameField> createState() => _PlayerNameFieldState();
}

class _PlayerNameFieldState extends State<PlayerNameField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCandidates = widget.candidates.isNotEmpty;
    return LayoutBuilder(
      builder: (context, box) => RawAutocomplete<String>(
        textEditingController: widget.controller,
        focusNode: _focus,
        optionsBuilder: (v) => matchPlayerNames(widget.candidates, v.text, exclude: widget.exclude),
        onSelected: (n) => widget.onChanged?.call(n),
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextField(
          key: widget.fieldKey,
          controller: controller,
          focusNode: focusNode,
          onChanged: widget.onChanged,
          onSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.text.isNotEmpty)
                  IconButton(
                    tooltip: tr('名前を消す', 'Clear name'),
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      controller.clear();
                      widget.onChanged?.call('');
                    },
                  ),
                if (hasCandidates)
                  IconButton(
                    tooltip: tr('過去のプレイヤーから選ぶ', 'Choose from past players'),
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () => focusNode.hasFocus ? focusNode.unfocus() : focusNode.requestFocus(),
                  ),
              ],
            ),
          ),
        ),
        optionsViewBuilder: (context, onSelected, options) {
          final theme = Theme.of(context);
          final list = options.toList();
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(6),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 260, maxWidth: box.maxWidth),
                child: ListView(
                  key: const ValueKey('player-name-options'),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text(
                          widget.controller.text.trim().isEmpty
                              ? tr('過去のプレイヤー（${list.length}人）。文字を入れると絞り込めます',
                                  'Past players (${list.length}). Type to filter')
                              : tr('「${widget.controller.text.trim()}」を含む名前（${list.length}人）',
                                  'Names containing "${widget.controller.text.trim()}" (${list.length})'),
                          style: theme.textTheme.bodySmall),
                    ),
                    for (final n in list)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline, size: 20),
                        title: Text(n),
                        onTap: () => onSelected(n),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
