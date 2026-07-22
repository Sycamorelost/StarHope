import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/models/models.dart';
import '../../../core/models/question.dart';
import '../../../core/models/share_meta.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/practice_exam_provider.dart';
import '../../../providers/question_provider.dart';
import '../../../services/database/database.dart';
import '../../../services/export_service.dart';
import '../../../services/question_serializer.dart';
import 'import_template_dialog.dart';

final ExportService _export = ExportService();

/// 批量导入 JSON/CSV/Excel/HTML/Markdown/DOCX
Future<void> showImportDialog(BuildContext context) async {
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('导入题库'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'pick'),
          child: const ListTile(
            leading: Icon(Icons.file_upload_outlined),
            title: Text('从文件导入'),
            subtitle: Text('CSV / HTML / Markdown'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'template'),
          child: const ListTile(
            leading: Icon(Icons.description_outlined),
            title: Text('查看模板与规范'),
            subtitle: Text('各文件类型字段规范与示例'),
          ),
        ),
      ],
    ),
  );
  if (action == null) return;
  if (!context.mounted) return;
  if (action == 'template') {
    showDialog(
      context: context,
      builder: (_) => const ImportTemplateDialog(),
    );
    return;
  }
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv', 'html', 'htm', 'md', 'markdown'],
  );
  if (result == null || result.files.single.path == null) return;
  final path = result.files.single.path!;

  if (!context.mounted) return;
  final extraTags = await _askImportTags(context);
  if (!context.mounted) return;
  final qb = context.read<QuestionBankProvider>();
  try {
    final imported = await qb.importFromFile(path, extraTags: extraTags);
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入完成'),
          content: Text('成功导入 ${imported.length} 道题目。'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('好的')),
          ],
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }
}

/// 导出题目：可选 starhope（含防伪，可回导）/ Markdown / CSV / HTML（纯文本，可回导）。
Future<void> showExportQuestionsDialog(
  BuildContext context, {
  required List<Question> questions,
}) async {
  if (questions.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('没有可导出的题目')));
    return;
  }
  final fmt = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('导出格式'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'starhope'),
          child: const ListTile(
            leading: Icon(Icons.verified_outlined),
            title: Text('StarHope 防伪包 (.starhope)'),
            subtitle: Text('含 SHA-256 校验，可重新导入'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'md'),
          child: const ListTile(
            leading: Icon(Icons.description_outlined),
            title: Text('Markdown (.md)'),
            subtitle: Text('可读、可重新导入'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'csv'),
          child: const ListTile(
            leading: Icon(Icons.table_chart_outlined),
            title: Text('CSV (.csv)'),
            subtitle: Text('表格，可重新导入'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'html'),
          child: const ListTile(
            leading: Icon(Icons.html_outlined),
            title: Text('HTML (.html)'),
            subtitle: Text('可读、可重新导入'),
          ),
        ),
      ],
    ),
  );
  if (fmt == null || !context.mounted) return;

  if (fmt == 'starhope') {
    await _exportQuestionsStarhope(context, questions);
    return;
  }
  // 纯文本格式
  final ext = fmt == 'md' ? 'md' : fmt;
  final out = await FilePicker.platform.saveFile(
    dialogTitle: '导出题库',
    fileName: 'starhope_questions_${DateTime.now().millisecondsSinceEpoch}.$ext',
  );
  if (out == null || !context.mounted) return;
  try {
    final content = fmt == 'md'
        ? QuestionSerializer.toMarkdown(questions)
        : fmt == 'csv'
            ? QuestionSerializer.toCsv(questions)
            : QuestionSerializer.toHtml(questions);
    await File(out).writeAsString(content);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已导出：$out')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }
}

Future<void> _exportQuestionsStarhope(
    BuildContext context, List<Question> questions) async {
  bool publicSocial = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('导出题库'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('将导出 ${questions.length} 道题目为 .starhope 文件'),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('公开社交账号'),
              subtitle: const Text('关闭时仅公开昵称'),
              value: publicSocial,
              onChanged: (v) => set(() => publicSocial = v),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导出')),
        ],
      ),
    ),
  );
  if (ok != true) return;

  final out = await FilePicker.platform.saveFile(
    dialogTitle: '导出题库',
    fileName:
        'starhope_questions_${DateTime.now().millisecondsSinceEpoch}.starhope',
  );
  if (out == null || !context.mounted) return;

  final auth = context.read<AuthProvider>();
  final meta = _export.buildMeta(auth.user!, ShareContentType.questionBank,
      publicSocial: publicSocial);
  try {
    await _export.exportQuestions(path: out, questions: questions, meta: meta);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已导出：$out')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }
}

/// 导入 .starhope 文件：校验 -> 分享者信息卡 -> 确认 -> 并入
Future<void> showImportStarHopeDialog(BuildContext context) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['starhope'],
  );
  if (result == null || result.files.single.path == null) return;
  final path = result.files.single.path!;

  final (file, error) = await _export.importAndVerify(path);
  if (file == null) {
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入失败'),
          content: Text(error ?? '未知错误'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('知道了')),
          ],
        ),
      );
    }
    return;
  }

  // 展示分享者信息卡
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('分享者信息'),
      content: ShareMetaCard(meta: file.meta),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认导入')),
      ],
    ),
  );
  if (confirmed != true) return;

  // 按内容类型分发到对应导入逻辑
  final ct = file.meta.contentType;
  int count;
  String msg;
  if (ct == ShareContentType.practiceRecord) {
    count = await _export.importPracticeRecord(file);
    if (context.mounted) {
      await context.read<PracticeExamProvider>().loadHistory();
    }
    msg = '已导入练习记录（含 $count 道题目）';
  } else if (ct == ShareContentType.examResultRecord) {
    count = await _export.importExamResultRecord(file);
    if (context.mounted) {
      await context.read<PracticeExamProvider>().loadRulesAndResults();
    }
    msg = '已导入考试成绩单（含 $count 道题目）';
  } else if (ct == ShareContentType.exam) {
    count = await _export.importExam(file);
    if (context.mounted) {
      await context.read<PracticeExamProvider>().loadRulesAndResults();
    }
    msg = '已导入 $count 条考试规则';
  } else {
    count = await _export.importQuestions(file);
    if (context.mounted) {
      await context.read<QuestionBankProvider>().load();
    }
    msg = '已导入 $count 道题目';
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// 导出练习记录：starhope（可回导）/ Markdown（可读报告）。
Future<void> exportPracticeRecordUI(BuildContext context, PracticeSession s) async {
  final all = await AppDatabase.instance.allQuestions();
  final map = {for (final q in all) q.id: q};
  final questions =
      s.questionIds.map((id) => map[id]).whereType<Question>().toList();
  if (!context.mounted) return;
  await _exportRecord(
    context,
    contentType: ShareContentType.practiceRecord,
    baseName: 'starhope_practice_${s.startedAt}',
    mdContent: _export.practiceToMarkdown(s, questions),
    onStarhope: (path, meta) =>
        _export.exportPracticeRecord(path: path, session: s, questions: questions, meta: meta),
  );
}

/// 导出考试成绩单：starhope（可回导）/ Markdown（可读报告）。
Future<void> exportExamResultRecordUI(BuildContext context, ExamResult r) async {
  final all = await AppDatabase.instance.allQuestions();
  final map = {for (final q in all) q.id: q};
  final questions =
      r.questionIds.map((id) => map[id]).whereType<Question>().toList();
  if (!context.mounted) return;
  await _exportRecord(
    context,
    contentType: ShareContentType.examResultRecord,
    baseName: 'starhope_exam_${r.submittedAt}',
    mdContent: _export.examResultToMarkdown(r, questions),
    onStarhope: (path, meta) =>
        _export.exportExamResultRecord(path: path, result: r, questions: questions, meta: meta),
  );
}

Future<void> _exportRecord(
  BuildContext context, {
  required ShareContentType contentType,
  required String baseName,
  required String mdContent,
  required Future<void> Function(String path, ShareMeta meta) onStarhope,
}) async {
  final fmt = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('导出格式'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'starhope'),
          child: const ListTile(
            leading: Icon(Icons.verified_outlined),
            title: Text('StarHope 防伪包 (.starhope)'),
            subtitle: Text('含校验，可在另一台机器导入还原'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'md'),
          child: const ListTile(
            leading: Icon(Icons.description_outlined),
            title: Text('Markdown 报告 (.md)'),
            subtitle: Text('可读答题卡（不可回导）'),
          ),
        ),
      ],
    ),
  );
  if (fmt == null || !context.mounted) return;
  try {
    if (fmt == 'starhope') {
      final auth = context.read<AuthProvider>();
      final meta = _export.buildMeta(auth.user!, contentType);
      final out = await FilePicker.platform.saveFile(
        dialogTitle: '导出',
        fileName: '$baseName.starhope',
      );
      if (out == null) return;
      await onStarhope(out, meta);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已导出：$out')));
      }
    } else {
      final out = await FilePicker.platform.saveFile(
        dialogTitle: '导出',
        fileName: '$baseName.md',
      );
      if (out == null) return;
      await File(out).writeAsString(mdContent);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已导出：$out')));
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }
}

/// 导入前询问统一标签（可选）
Future<List<String>> _askImportTags(BuildContext context) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('导入选项'),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '为本次导入的题目添加统一标签',
          hintText: '可选，逗号分隔，如：2024期末、第一章',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('跳过')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('导入')),
      ],
    ),
  );
  if (ok != true) return const [];
  return c.text
      .split(RegExp(r'[,，;；\s]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// 分享者信息卡组件
class ShareMetaCard extends StatelessWidget {
  final ShareMeta meta;
  const ShareMetaCard({super.key, required this.meta});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.person, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(meta.nickname,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('上传者为 ${meta.nickname}',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _row('内容类型', _contentTypeLabel(meta.contentType), cs),
        _row('导出时间', _formatTime(meta.exportedAt), cs),
        _row('社交账号', meta.displaySocial, cs),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.tertiaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.verified, size: 16, color: cs.onTertiaryContainer),
              const SizedBox(width: 6),
              Expanded(
                child: Text('SHA-256 校验通过，文件完整可信',
                    style: TextStyle(
                        fontSize: 12, color: cs.onTertiaryContainer)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String k, String v, ColorScheme cs) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 72,
                child: Text(k,
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 12))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  String _contentTypeLabel(ShareContentType t) {
    switch (t) {
      case ShareContentType.questionBank:
        return '题库';
      case ShareContentType.readingMaterial:
        return '阅读资料';
      case ShareContentType.fullBackup:
        return '全库备份';
      case ShareContentType.notes:
        return '笔记';
      case ShareContentType.exam:
        return '考试';
      case ShareContentType.practiceRecord:
        return '练习记录';
      case ShareContentType.examResultRecord:
        return '考试成绩单';
    }
  }

  String _formatTime(String iso) {
    try {
      return DateTime.parse(iso).toLocal().toString().substring(0, 19);
    } catch (_) {
      return iso;
    }
  }
}

// 引用常量避免未使用
// ignore: unused_element
const String _kApp = AppConstants.appName;
