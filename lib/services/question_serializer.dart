import 'package:csv/csv.dart';

import '../core/constants.dart';
import '../core/models/question.dart';

/// 题库序列化（导出）：Markdown / CSV / HTML。
///
/// 格式与 [QuestionImportService] 的解析规范严格对应，保证导出文件可被重新导入
/// （round-trip）。字段：题型 / 题干 / 选项 / 答案 / 解析 / 标签 / 难度。
/// 注：题干/解析中的 base64 内嵌图片在 MD/HTML 中保留（可回导），CSV 中因单元格
/// 体积建议仅用于纯文本题库。
class QuestionSerializer {
  /// Markdown：每个题目以 `---` 分隔，字段为 `键: 值`。
  static String toMarkdown(List<Question> qs) {
    final sb = StringBuffer();
    sb.writeln('<!-- StarHope 题库导出 · 共 ${qs.length} 题 · 可重新导入 -->');
    for (var i = 0; i < qs.length; i++) {
      final q = qs[i];
      sb.writeln('---');
      sb.writeln('题型: ${_typeLabel(q.type)}');
      sb.writeln('题干: ${q.stem.isEmpty ? '（无题干）' : q.stem}');
      if (q.options.isNotEmpty) {
        sb.writeln('选项: ${_formatOptions(q)}');
      }
      sb.writeln('答案: ${_answerText(q)}');
      if (q.explanation.isNotEmpty) sb.writeln('解析: ${q.explanation}');
      if (q.tags.isNotEmpty) sb.writeln('标签: ${q.tags.join(', ')}');
      sb.writeln('难度: ${q.difficulty}');
    }
    return sb.toString();
  }

  /// CSV：表头 type,stem,options,answer,explanation,tags,difficulty。
  static String toCsv(List<Question> qs) {
    final rows = <List<String>>[
      const ['type', 'stem', 'options', 'answer', 'explanation', 'tags', 'difficulty'],
      for (final q in qs)
        [
          _typeLabel(q.type),
          q.stem,
          q.options.isEmpty ? '' : _formatOptions(q),
          _answerText(q),
          q.explanation,
          q.tags.join(', '),
          '${q.difficulty}',
        ],
    ];
    return const ListToCsvConverter(eol: '\n').convert(rows);
  }

  /// HTML：每个题目一个 .question 块（.stem + .options>li + 答案行）。
  static String toHtml(List<Question> qs) {
    final sb = StringBuffer();
    sb.writeln('<!DOCTYPE html><html><head><meta charset="utf-8">');
    sb.writeln('<title>StarHope 题库导出（${qs.length} 题）</title></head><body>');
    for (final q in qs) {
      sb.writeln('<div class="question">');
      sb.writeln('  <div class="stem">${_esc(q.stem.isEmpty ? '（无题干）' : q.stem)}</div>');
      if (q.options.isNotEmpty) {
        sb.writeln('  <ul class="options">');
        for (var i = 0; i < q.options.length; i++) {
          sb.writeln(
              '    <li>${_esc(_letter(i))}. ${_esc(q.options[i])}</li>');
        }
        sb.writeln('  </ul>');
      }
      sb.writeln('  <p>答案: ${_esc(_answerText(q))}</p>');
      if (q.explanation.isNotEmpty) {
        sb.writeln('  <p class="explanation">解析: ${_esc(q.explanation)}</p>');
      }
      sb.writeln('</div>');
    }
    sb.writeln('</body></html>');
    return sb.toString();
  }

  static String _formatOptions(Question q) {
    return List.generate(q.options.length, (i) => '${_letter(i)}. ${q.options[i]}')
        .join(' || ');
  }

  static String _answerText(Question q) => renderAnswer(q, q.answer);

  /// 渲染某答案串（题目的标准答案或用户的作答）为可读文本。
  static String renderAnswer(Question q, String ans) {
    if (ans.isEmpty) return '（未作答）';
    if (q.type == QuestionType.fill || q.type == QuestionType.essay) {
      return ans;
    }
    if (q.type == QuestionType.judge) {
      return ans == '1' ? '正确' : '错误';
    }
    final indices =
        ans.split(',').map((s) => int.tryParse(s.trim())).whereType<int>();
    return indices
        .where((i) => i >= 0 && i < q.options.length)
        .map(_letter)
        .join('');
  }

  static String _letter(int i) => String.fromCharCode(65 + i);

  static String _typeLabel(QuestionType t) {
    switch (t) {
      case QuestionType.single:
        return '单选';
      case QuestionType.multiple:
        return '多选';
      case QuestionType.fill:
        return '填空';
      case QuestionType.judge:
        return '判断';
      case QuestionType.undefined:
        return '不定项';
      case QuestionType.essay:
        return '问答';
    }
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
