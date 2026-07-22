import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
// markdown 为 flutter_markdown 的传递依赖；直接引用其 InlineSyntax/Element 以扩展内联语法。
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;

/// 离线公式渲染：在 Markdown 中以 `{{type|arg1|arg2|...}}` 形式嵌入公式，
/// 由 [FormulaSyntax] 识别、[FormulaBuilder] 渲染为 2D 结构（分数/根号/求和/上下标…）。
/// 无需联网、无需额外依赖。
///
/// 支持类型：
/// - `{{frac|分子|分母}}` 分数
/// - `{{sqrt|被开方数}}` 根号；`{{nroot|次数|被开方数}}` n 次根
/// - `{{sup|指数}}` 上标；`{{sub|下标}}` 下标
/// - `{{sum|下限|上限}}` 求和；`{{prod|下限|上限}}` 连乘
/// - `{{int|下限|上限}}` 定积分；`{{lim|条件}}` 极限
/// - `{{mat|a|b|c|d}}` 矩阵（按行优先，自动 2 列）
class FormulaSyntax extends md.InlineSyntax {
  FormulaSyntax() : super(r'\{\{(\w+)((?:\|[^|{}]+)*)\}\}', startCharacter: 123);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final type = match.group(1)!;
    final argsStr = match.group(2) ?? '';
    final args = argsStr
        .split('|')
        .where((s) => s.isNotEmpty)
        .toList();
    parser.addNode(md.Element.text('formula', [type, ...args].join('|')));
    return true;
  }
}

class FormulaBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style = parentStyle ?? preferredStyle;
    return renderFormula(element.textContent, style);
  }
}

/// 把公式 token 各部分组装成可读的 markdown token 字符串。
String formulaToken(String type, List<String> args) {
  final clean = args.map((a) => a.replaceAll('|', ' ').trim()).join('|');
  return '{{$type|$clean}}';
}

/// 渲染公式 token（textContent 形如 `frac|a|b`）为内联 Widget。
Widget renderFormula(String content, TextStyle? base) {
  final parts = content.split('|');
  final type = parts.first;
  final args = parts.skip(1).toList();
  final color = base?.color;
  final fs = base?.fontSize ?? 14;
  TextStyle small([double f = 0.62]) =>
      (base ?? const TextStyle()).copyWith(fontSize: fs * f, color: color);

  Widget line() => Container(height: 1.4, color: color ?? const Color(0xFF000000));

  switch (type) {
    case 'frac':
      return IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(args.isNotEmpty ? args[0] : '', style: small(0.8)),
            Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: line()),
            Text(args.length > 1 ? args[1] : '', style: small(0.8)),
          ],
        ),
      );
    case 'sqrt':
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('√',
              style: (base ?? const TextStyle())
                  .copyWith(fontSize: fs * 1.15, color: color)),
          Container(
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: color ?? const Color(0xFF000000))),
            ),
            padding: const EdgeInsets.only(top: 1),
            child: Text(args.isNotEmpty ? args[0] : '', style: small(0.8)),
          ),
        ],
      );
    case 'nroot':
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(args.isNotEmpty ? args[0] : '', style: small(0.55)),
              Text('√', style: (base ?? const TextStyle()).copyWith(fontSize: fs * 1.15)),
            ],
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: color ?? const Color(0xFF000000))),
            ),
            padding: const EdgeInsets.only(top: 1),
            child: Text(args.length > 1 ? args[1] : '', style: small(0.8)),
          ),
        ],
      );
    case 'sup':
      return Transform.translate(
        offset: Offset(0, -fs * 0.32),
        child: Text(args.isNotEmpty ? args[0] : '', style: small(0.72)),
      );
    case 'sub':
      return Transform.translate(
        offset: Offset(0, fs * 0.28),
        child: Text(args.isNotEmpty ? args[0] : '', style: small(0.72)),
      );
    case 'sum':
    case 'prod':
      final sym = type == 'sum' ? '∑' : '∏';
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(args.length > 1 ? args[1] : '', style: small()),
          Text(sym,
              style: (base ?? const TextStyle()).copyWith(fontSize: fs * 1.4)),
          Text(args.isNotEmpty ? args[0] : '', style: small()),
        ],
      );
    case 'int':
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(args.length > 1 ? args[1] : '', style: small()),
              const SizedBox(height: 2),
              Text(args.isNotEmpty ? args[0] : '', style: small()),
            ],
          ),
          Text('∫',
              style: (base ?? const TextStyle())
                  .copyWith(fontSize: fs * 1.6, height: 0.9)),
        ],
      );
    case 'lim':
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('lim', style: small(0.7)),
              Text(args.isNotEmpty ? args[0] : '', style: small(0.6)),
            ],
          ),
        ],
      );
    case 'mat':
      // 矩阵：按行优先 2 列（不足补空），外加方括号
      final cells = List<String>.from(args);
      while (cells.length % 2 != 0) {
        cells.add('');
      }
      final rows = <Widget>[];
      for (var i = 0; i < cells.length; i += 2) {
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 22, child: Text(cells[i], style: small(0.78))),
              SizedBox(width: 22, child: Text(cells[i + 1], style: small(0.78))),
            ],
          ),
        ));
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('[', style: (base ?? const TextStyle()).copyWith(fontSize: fs * 1.4)),
          IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: rows,
            ),
          ),
          Text(']', style: (base ?? const TextStyle()).copyWith(fontSize: fs * 1.4)),
        ],
      );
    default:
      // 未知类型：原样显示
      return Text('{$content}', style: base);
  }
}
