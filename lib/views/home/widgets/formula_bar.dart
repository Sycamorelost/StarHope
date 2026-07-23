import 'package:flutter/material.dart';

import '../../common/formula_render.dart';

/// 公式与符号工具栏：插入到任意 [TextEditingController] 的光标处。
///
/// 采用 WPS 式「模板 + 填空」：点击公式模板（分数/根号/求和…）弹出对应字段，
/// 填好后插入 `{{type|...}}` token，由 MarkdownBody 经 [FormulaBuilder] 离线渲染
/// 为 2D 结构（无需联网、无需新依赖）。另提供常用 Unicode 数学符号一键插入。
class FormulaBar extends StatefulWidget {
  final TextEditingController controller;
  const FormulaBar({super.key, required this.controller});

  @override
  State<FormulaBar> createState() => _FormulaBarState();
}

class _FormulaBarState extends State<FormulaBar> {
  bool _expanded = false;

  /// 在光标处插入文本（无选中位置则追加到末尾）。
  void _insert(String text) {
    final c = widget.controller;
    final pos = c.selection.isValid ? c.selection.baseOffset : c.text.length;
    final newText = c.text.substring(0, pos) + text + c.text.substring(pos);
    c.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + text.length),
    );
  }

  Future<void> _pickTemplate(
      String type, String title, List<String> fieldLabels) async {
    final controllers =
        List.generate(fieldLabels.length, (_) => TextEditingController());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < fieldLabels.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: controllers[i],
                    autofocus: i == 0,
                    decoration: InputDecoration(
                        labelText: fieldLabels[i], isDense: true),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('插入')),
        ],
      ),
    );
    if (ok == true) {
      final args = controllers.map((c) => c.text.isEmpty ? '?' : c.text).toList();
      _insert(formulaToken(type, args));
    }
    for (final c in controllers) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.functions, size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                  Text('公式与符号',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.primary)),
                  const Spacer(),
                  Text('点此展开/收起',
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('公式模板（点击后填写）',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _tpl('分数', () => _pickTemplate(
                          'frac', '分数', ['分子', '分母'])),
                      _tpl('上标 xⁿ', () => _insert('{{sup|2}}')),
                      _tpl('下标 xₙ', () => _insert('{{sub|n}}')),
                      _tpl('根号', () => _pickTemplate(
                          'sqrt', '根号', ['被开方数'])),
                      _tpl('n 次根', () => _pickTemplate(
                          'nroot', 'n 次根', ['次数', '被开方数'])),
                      _tpl('求和 ∑', () => _pickTemplate(
                          'sum', '求和', ['下限', '上限'])),
                      _tpl('连乘 ∏', () => _pickTemplate(
                          'prod', '连乘', ['下限', '上限'])),
                      _tpl('定积分 ∫', () => _pickTemplate(
                          'int', '定积分', ['下限', '上限'])),
                      _tpl('极限', () => _pickTemplate(
                          'lim', '极限', ['条件 (如 x→0)'])),
                      _tpl('2×2 矩阵', () => _pickTemplate(
                          'mat', '2×2 矩阵', ['a', 'b', 'c', 'd'])),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('常用符号（点击插入，离线可用）',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final s in _symbols)
                        InkWell(
                          onTap: () => _insert(s),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 30),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 5),
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Text(s,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontFamily: 'Segoe UI Symbol')),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tpl(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onTap,
    );
  }
}

const List<String> _symbols = [
  '²', '³', '⁰', '¹', '⁴', '⁵', 'ⁿ',
  '₀', '₁', '₂', '₃', '₄', '₅', '₆',
  '±', '×', '÷', '√', '∑', '∏', '∫', '∮', '∞', '∝', '∂', '∇',
  '≤', '≥', '≠', '≈', '≡', '∈', '∉', '⊂', '⊆', '⊃', '⊇', '∪', '∩',
  'α', 'β', 'γ', 'δ', 'ε', 'θ', 'λ', 'μ', 'ν', 'π', 'ρ', 'σ', 'τ', 'φ', 'ψ', 'ω',
  'Γ', 'Δ', 'Θ', 'Λ', 'Σ', 'Π', 'Φ', 'Ω',
  '→', '←', '↔', '⇒', '⇐', '⇔', '↑', '↓',
  '∀', '∃', '∘', '⊕', '⊗', '·', '°', '′', '″', '∠', '⊥', '∥',
];
