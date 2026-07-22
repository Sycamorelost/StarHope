import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/constants.dart';
import '../../../core/formula_render.dart';
import '../../../core/models/question.dart';
import 'question_tile.dart';

/// 题型徽章（取代 practice/exam 页各自的 _typeChip）。
class QTypeChip extends StatelessWidget {
  final QuestionType type;
  const QTypeChip({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(type.label,
          style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer)),
    );
  }
}

/// 选项条：单选/多选/判断共用。disabled 时不可点（已提交/已判分）。
/// 选项文本经 Markdown 渲染，故选项内可含 `![](data:image/...;base64,...)` 图片。
class OptionTile extends StatelessWidget {
  final String text;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  const OptionTile({
    super.key,
    required this.text,
    required this.selected,
    this.disabled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? cs.primary : cs.outline),
            const SizedBox(width: 10),
            Expanded(
              child: MarkdownBody(
                data: text.isEmpty ? '（空）' : text,
                selectable: true,
                sizedImageBuilder: (c) =>
                    markdownImageBuilder(c.uri, c.title, c.alt),
                inlineSyntaxes: [FormulaSyntax()],
                builders: {'formula': FormulaBuilder()},
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                    .copyWith(p: const TextStyle(fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 答案输入区（按题型自适应）：单选/多选/判断→OptionTile 列；填空/主观→文本框。
/// [enabled]=false 时只读（已提交/已判分）。取代 practice/exam 页各自的 _answerInput。
class AnswerInput extends StatelessWidget {
  final Question question;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final String essayLabel;
  final String fillLabel;

  const AnswerInput({
    super.key,
    required this.question,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.essayLabel = '作答（主观题）',
    this.fillLabel = '输入答案',
  });

  @override
  Widget build(BuildContext context) {
    final q = question;
    if (q.type == QuestionType.essay || q.type == QuestionType.fill) {
      return _TextInputField(
        value: value,
        enabled: enabled,
        maxLines: q.type == QuestionType.essay ? 6 : 1,
        label: q.type == QuestionType.essay ? essayLabel : fillLabel,
        onChanged: onChanged,
      );
    }
    if (q.type == QuestionType.judge) {
      return Row(
        children: [
          Expanded(
            child: OptionTile(
              text: '正确',
              selected: value == '1',
              disabled: !enabled,
              onTap: () => onChanged('1'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OptionTile(
              text: '错误',
              selected: value == '0',
              disabled: !enabled,
              onTap: () => onChanged('0'),
            ),
          ),
        ],
      );
    }
    // single / multiple / undefined
    final multi = q.type == QuestionType.multiple ||
        q.type == QuestionType.undefined;
    final selected = value
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
    return Column(
      children: [
        for (var i = 0; i < q.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OptionTile(
              text: q.options[i],
              selected: selected.contains(i),
              disabled: !enabled,
              onTap: () {
                if (multi) {
                  final ns = Set<int>.from(selected);
                  if (ns.contains(i)) {
                    ns.remove(i);
                  } else {
                    ns.add(i);
                  }
                  onChanged((ns.toList()..sort()).join(','));
                } else {
                  onChanged('$i');
                }
              },
            ),
          ),
      ],
    );
  }
}

/// 文本作答框：自管 TextEditingController，仅在外部值与当前文本不一致时同步，
/// 避免重建时光标跳动（取代各页 build 内 new TextEditingController 的写法）。
class _TextInputField extends StatefulWidget {
  final String value;
  final bool enabled;
  final int maxLines;
  final String label;
  final ValueChanged<String> onChanged;
  const _TextInputField({
    required this.value,
    required this.enabled,
    required this.maxLines,
    required this.label,
    required this.onChanged,
  });

  @override
  State<_TextInputField> createState() => _TextInputFieldState();
}

class _TextInputFieldState extends State<_TextInputField> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _TextInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅在外部值变化且与当前文本不一致时同步（用户输入时不打断光标）
    if (widget.value != _c.text) {
      _c.text = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      enabled: widget.enabled,
      maxLines: widget.maxLines,
      decoration: InputDecoration(labelText: widget.label),
      onChanged: widget.onChanged,
    );
  }
}

/// 把内部答案串渲染成可读文本（取代 practice/exam 页的 _displayAnswer）。
String displayAnswer(Question q, String ans) {
  if (q.type == QuestionType.fill) return ans;
  if (q.type == QuestionType.essay) return ans;
  if (q.type == QuestionType.judge) {
    if (ans.isEmpty) return '';
    return ans == '1' ? '正确' : '错误';
  }
  final indices =
      ans.split(',').map((s) => int.tryParse(s.trim())).whereType<int>();
  return indices
      .map((i) => i >= 0 && i < q.options.length
          ? String.fromCharCode(65 + i)
          : '?')
      .join(',');
}
