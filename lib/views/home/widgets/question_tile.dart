import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/constants.dart';
import '../../common/formula_render.dart';
import '../../../core/models/question.dart';
import '../../common/glass.dart';

class QuestionTile extends StatelessWidget {
  final Question question;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onAiExplain;
  final VoidCallback? onDelete;

  const QuestionTile({
    super.key,
    required this.question,
    this.selected = false,
    this.selectionMode = false,
    required this.onTap,
    required this.onLongPress,
    required this.onAiExplain,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectionMode)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: selected ? cs.primary : cs.outline,
                  size: 20,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _typeBadge(context, question.type),
                      const SizedBox(width: 6),
                      if (question.isFromShare)
                        SourceBadge(
                          nickname: question.sourceNickname,
                          authorId: question.sourceAuthorId,
                        ),
                      const Spacer(),
                      _difficulty(context, question.difficulty),
                    ],
                  ),
                  const SizedBox(height: 6),
                  MarkdownPreview(
                      question.stem.isEmpty ? '（无题干）' : question.stem),
                  if (question.practiceCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_statsText(question),
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant)),
                    ),
                  if (question.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: question.tags
                          .map((t) => Chip(
                                label: Text(t,
                                    style: const TextStyle(fontSize: 10)),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'ai', child: Text('让 AI 解释')),
                const PopupMenuItem(value: 'extend', child: Text('拓展知识')),
                if (onDelete != null)
                  const PopupMenuItem(value: 'delete', child: Text('删除题目')),
              ],
              onSelected: (v) {
                if (v == 'delete') {
                  onDelete!.call();
                } else {
                  onAiExplain();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeBadge(BuildContext context, QuestionType t) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(t.label,
          style: TextStyle(
              fontSize: 11,
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w500)),
    );
  }

  Widget _difficulty(BuildContext context, int d) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            i < d ? Icons.star : Icons.star_border,
            size: 12,
            color: Theme.of(context).colorScheme.tertiary,
          ),
      ],
    );
  }
}

/// 简短 Markdown 预览（用于题目详情）
class MarkdownPreview extends StatelessWidget {
  final String data;
  final bool selectable;
  const MarkdownPreview(this.data, {super.key, this.selectable = false});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    return MarkdownBody(
      data: data,
      selectable: selectable,
      sizedImageBuilder: (c) => markdownImageBuilder(c.uri, c.title, c.alt),
      inlineSyntaxes: [FormulaSyntax()],
      builders: {'formula': FormulaBuilder()},
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: const TextStyle(fontSize: 14, height: 1.5),
      ),
    );
  }
}

/// Markdown 图片渲染：支持 `data:image/...;base64,...`（内嵌）与 `file://` 本地图，
/// 其余走网络。供 MarkdownPreview / OptionTile 共用。
Widget markdownImageBuilder(Uri uri, String? title, String? alt) {
  if (uri.isScheme('data')) {
    final comma = uri.path.indexOf(',');
    if (comma > 0) {
      final meta = uri.path.substring(0, comma);
      final payload = uri.path.substring(comma + 1);
      try {
        final bytes = meta.contains('base64') ? base64Decode(payload) : null;
        if (bytes != null) {
          return Image.memory(Uint8List.fromList(bytes),
              errorBuilder: (_, __, ___) => const SizedBox.shrink());
        }
      } catch (_) {
        return const SizedBox.shrink();
      }
    }
    return const SizedBox.shrink();
  }
  if (uri.isScheme('file')) {
    return Image.file(File.fromUri(uri),
        errorBuilder: (_, __, ___) => const SizedBox.shrink());
  }
  return Image.network(uri.toString(),
      errorBuilder: (_, __, ___) => const SizedBox.shrink());
}

/// 题目使用统计文本（练 N 次 · 正确率 X% · 最近 Y 前）。未练返回空串。
String _statsText(Question q) {
  if (q.practiceCount <= 0) return '';
  final acc = (q.correctCount / q.practiceCount * 100).round();
  String when = '';
  if (q.lastPracticedAt != null) {
    final days =
        ((DateTime.now().millisecondsSinceEpoch - q.lastPracticedAt!) / 86400000)
            .floor();
    when = days <= 0
        ? '今天'
        : days < 30
            ? '$days 天前'
            : '${(days / 30).floor()} 个月前';
  }
  return '练 ${q.practiceCount} 次 · 正确率 $acc%${when.isEmpty ? '' : ' · $when'}';
}
