import 'dart:io';

import 'package:csv/csv.dart';
import 'package:html/parser.dart' as html_parser;

import '../core/constants.dart';
import '../core/crypto/crypto_service.dart';
import '../core/models/question.dart';

/// 题库批量导入服务（服务层）
///
/// 支持 CSV / HTML / Markdown。可自定义列映射。
class QuestionImportService {
  /// 列映射：将外部字段名映射到题目字段
  /// key = 外部列名/键名，value = Question 字段名
  static const Map<String, String> defaultCsvMapping = {
    'type': 'type',
    '题型': 'type',
    'stem': 'stem',
    '题干': 'stem',
    'question': 'stem',
    'options': 'options',
    '选项': 'options',
    'answer': 'answer',
    '答案': 'answer',
    'explanation': 'explanation',
    '解析': 'explanation',
    'tags': 'tags',
    '标签': 'tags',
    'difficulty': 'difficulty',
    '难度': 'difficulty',
  };

  /// 自动识别文件类型并解析（仅支持 csv / html / md）
  Future<List<Question>> importFile(String path,
      {Map<String, String>? mapping, String? htmlSelector}) async {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'csv':
        return parseCsv(await File(path).readAsString(), mapping: mapping);
      case 'html':
      case 'htm':
        return parseHtml(await File(path).readAsString(),
            selector: htmlSelector);
      case 'md':
      case 'markdown':
        return parseStructuredText(await File(path).readAsString());
      default:
        throw UnsupportedError('不支持的导入格式: $ext（仅支持 csv / html / md）');
    }
  }

  /// 统一结构化文本解析（适用于 Markdown）。
  ///
  /// 规范：每个题目以 `---` 分隔，字段为 `键: 值` 形式。
  /// 只有已知字段键开头的行才算字段定义，其余行（含冒号/多行）作为上一字段续行。
  /// ```
  /// 题型: 单选
  /// 题干: ...
  /// 选项: A. xxx || B. yyy || C. zzz || D. www
  /// 答案: A
  /// 解析: ...
  /// 标签: tag1, tag2
  /// 难度: 3
  /// ```
  List<Question> parseStructuredText(String content) {
    final now = DateTime.now().millisecondsSinceEpoch;
    const keyMap = <String, String>{
      '题型': 'type', 'type': 'type',
      '题干': 'stem', 'stem': 'stem', '题目': 'stem', 'question': 'stem',
      '选项': 'options', 'options': 'options',
      '答案': 'answer', 'answer': 'answer',
      '解析': 'explanation', 'explanation': 'explanation', '分析': 'explanation',
      '标签': 'tags', 'tags': 'tags',
      '难度': 'difficulty', 'difficulty': 'difficulty',
    };
    final blocks = content
        .split(RegExp(r'^---+\s*$', multiLine: true))
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();
    final out = <Question>[];
    for (final block in blocks) {
      final fields = <String, String>{};
      String? currentKey;
      for (final rawLine in block.split('\n')) {
        final trimmed = rawLine.trim();
        if (trimmed.isEmpty) continue;
        final m = RegExp(r'^([^:：\s]+)\s*[:：]\s*(.*)$').firstMatch(trimmed);
        if (m != null) {
          final g1 = m.group(1)!;
          final normKey = keyMap[g1] ?? keyMap[g1.toLowerCase()];
          if (normKey != null) {
            final value = m.group(2)!.trim();
            currentKey = normKey;
            if (value.isEmpty) {
              fields[normKey] = fields[normKey] ?? '';
            } else {
              fields[normKey] =
                  (fields.containsKey(normKey) && fields[normKey]!.isNotEmpty)
                      ? '${fields[normKey]}\n$value'
                      : value;
            }
            continue;
          }
        }
        // 非已知字段开头 → 追加为当前字段续行
        if (currentKey != null) {
          fields[currentKey] = fields[currentKey]!.isEmpty
              ? trimmed
              : '${fields[currentKey]}\n$trimmed';
        }
      }
      if (fields.isEmpty) continue;
      final q = _buildFromFields(fields, now);
      if (q != null) out.add(q);
    }
    return out;
  }

  // ---------------- CSV ----------------
  List<Question> parseCsv(String content, {Map<String, String>? mapping}) {
    final map = mapping ?? defaultCsvMapping;
    final rows = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(content);
    if (rows.length < 2) return const [];
    final header = rows.first.map((e) => e.toString().trim()).toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = <Question>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((c) => c.toString().trim().isEmpty)) continue;
      final fields = <String, String>{};
      for (var c = 0; c < header.length && c < row.length; c++) {
        final target = map[header[c]] ?? header[c].toLowerCase();
        fields[target] = row[c].toString().trim();
      }
      final q = _buildFromFields(fields, now);
      if (q != null) out.add(q);
    }
    return out;
  }

  // ---------------- HTML ----------------
  /// [selector] 为 CSS 选择器定位单个题目块；默认按 .question/.problem/.item 定位。
  /// 块内优先结构化提取题干(.stem)、选项(.options li)、答案(文本"答案: X")，
  /// 避免把 <li> 选项误判为独立题目。
  List<Question> parseHtml(String content, {String? selector}) {
    final document = html_parser.parse(content);
    final blocks = (selector != null && selector.isNotEmpty)
        ? document.querySelectorAll(selector)
        : document.querySelectorAll(
            '.question, .problem, .item, [class*="question"]');
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = <Question>[];
    for (final block in blocks) {
      final text = block.text.trim();
      if (text.isEmpty) continue;
      // 题干：优先 .stem/.title/h* 子元素
      final stemEl = block.querySelector(
          '.stem, .question-stem, .title, h1, h2, h3');
      var stem = stemEl?.text.trim() ?? '';
      // 选项：优先结构化 .options li / .option
      var options = block
          .querySelectorAll('.options li, .option')
          .map((e) => e.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      // 答案：从文本提取"答案: X"（兼容 <p>答案: C</p> 无 class）
      final answerReg =
          RegExp(r'(?:答案|Answer|answer)\s*[:：]\s*([A-Za-z0-9,，、；;\s]+)');
      final answerMatch = answerReg.firstMatch(text);
      var answer = answerMatch?.group(1)?.trim() ?? '';
      // 题干 fallback：结构化为空时取文本到答案前
      if (stem.isEmpty) {
        stem =
            answerMatch != null ? text.substring(0, answerMatch.start).trim() : text;
      }
      // 选项 fallback：结构化为空时用 A./B. 正则
      if (options.isEmpty) {
        final optReg = RegExp(r'([A-Z])[\.、)]\s*([^\n]+)');
        for (final m in optReg.allMatches(text)) {
          options.add('${m.group(1)}. ${m.group(2)!.trim()}');
        }
      }
      if (stem.isEmpty) continue;
      // 按答案字母数推断题型：多字母答案 → 多选；单字母 → 单选；无选项 → 填空
      final answerLetters = RegExp(r'[A-Za-z]').allMatches(answer).length;
      final QuestionType type;
      if (options.isEmpty) {
        type = QuestionType.fill;
      } else if (answerLetters > 1) {
        type = QuestionType.multiple;
      } else {
        type = QuestionType.single;
      }
      out.add(Question(
        id: CryptoService.generateId(),
        type: type,
        stem: stem,
        options: options,
        answer: _normalizeAnswer(answer, type, options),
        createdAt: now,
        updatedAt: now,
      ));
    }
    return out;
  }

  // ---------------- 构建工具 ----------------
  Question? _buildFromFields(Map<String, String> f, int now) {
    final stem = f['stem'] ?? '';
    if (stem.isEmpty) return null;
    final type = _parseType(f['type']);
    final options = _parseOptions(f['options'], type);
    final answer = _normalizeAnswer(f['answer'] ?? '', type, options);
    return Question(
      id: CryptoService.generateId(),
      type: type,
      stem: stem,
      options: options,
      answer: answer,
      explanation: f['explanation'] ?? '',
      tags: _parseTags(f['tags']),
      difficulty: int.tryParse(f['difficulty'] ?? '') ?? 3,
      createdAt: now,
      updatedAt: now,
    );
  }

  QuestionType _parseType(String? s) {
    if (s == null || s.isEmpty) return QuestionType.single;
    final v = s.trim().toLowerCase();
    if (v.contains('多选')) return QuestionType.multiple;
    if (v.contains('不定')) return QuestionType.undefined;
    if (v.contains('填空')) return QuestionType.fill;
    if (v.contains('判断')) return QuestionType.judge;
    if (v.contains('问答') || v.contains('主观') || v == 'essay') {
      return QuestionType.essay;
    }
    if (v == 'multiple' || v == 'multi') return QuestionType.multiple;
    if (v == 'fill') return QuestionType.fill;
    if (v == 'judge' || v == 'truefalse') return QuestionType.judge;
    if (v == 'undefined') return QuestionType.undefined;
    return QuestionType.single;
  }

  List<String> _parseOptions(String? raw, QuestionType type) {
    if (raw == null || raw.isEmpty) return const [];
    // 选项以 || 或换行分隔
    final parts = raw.split(RegExp(r'\s*\|\|\s*|\n'));
    return parts.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  String _normalizeAnswer(String raw, QuestionType type, List<String> options) {
    // 填空/主观题：保留原文（|| 多空分隔仅对填空有意义，主观题整体保留）
    if (type == QuestionType.fill || type == QuestionType.essay) {
      return raw.trim().replaceAll('，', ',');
    }
    // 非填空：将各种分隔符（逗号/分号/竖线/顿号/全角）统一为逗号
    final a = raw
        .trim()
        .replaceAll('；', ';')
        .replaceAll('|', ',')
        .replaceAll(';', ',')
        .replaceAll('、', ',')
        .replaceAll('，', ',');
    if (type == QuestionType.judge) {
      if (a.contains('对') || a.contains('正确') ||
          a.toLowerCase() == 'true' || a.toLowerCase() == 't' || a == '1') {
        return '1';
      }
      return '0';
    }
    // 单选/多选/不定项：将字母 A/B/C 或数字转为索引
    final indices = <int>[];
    for (final ch in a.toUpperCase().split('')) {
      if (ch.codeUnitAt(0) >= 65 && ch.codeUnitAt(0) <= 90) {
        indices.add(ch.codeUnitAt(0) - 65);
      } else if (RegExp(r'\d').hasMatch(ch)) {
        indices.add(int.parse(ch));
      }
    }
    indices.sort();
    return indices.toSet().toList().join(',');
  }

  List<String> _parseTags(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw
        .split(RegExp(r'[,，;；\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}

// 引用常量避免未使用警告
// ignore: unused_element
const int _kFmt = AppConstants.formatVersion;
