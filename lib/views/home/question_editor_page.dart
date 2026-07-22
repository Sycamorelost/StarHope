import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/models/models.dart';
import '../../core/models/question.dart';
import '../../providers/question_provider.dart';
import '../common/glass.dart';
import '../common/theme.dart';
import 'widgets/formula_bar.dart';
import 'widgets/question_tile.dart';

class QuestionEditorPage extends StatefulWidget {
  final Question? question;
  const QuestionEditorPage({super.key, this.question});

  @override
  State<QuestionEditorPage> createState() => _QuestionEditorPageState();
}

class _QuestionEditorPageState extends State<QuestionEditorPage> {
  late QuestionType _type;
  late TextEditingController _stem;
  late TextEditingController _explanation;
  late TextEditingController _tags;
  late TextEditingController _answer;
  late TextEditingController _source;
  late List<TextEditingController> _options;
  int _difficulty = 3;
  bool _preview = false;
  String? _folderId;

  @override
  void initState() {
    super.initState();
    final q = widget.question;
    _type = q?.type ?? QuestionType.single;
    _stem = TextEditingController(text: q?.stem ?? '');
    _explanation = TextEditingController(text: q?.explanation ?? '');
    _tags = TextEditingController(text: q?.tags.join(', ') ?? '');
    _answer = TextEditingController(text: q?.answer ?? '');
    _source = TextEditingController(text: q?.sourceNickname ?? '');
    _options = (q?.options.isNotEmpty ?? false)
        ? q!.options.map((o) => TextEditingController(text: o)).toList()
        : [TextEditingController(), TextEditingController()];
    if (_type == QuestionType.judge && _options.length != 2) {
      _options = [
        TextEditingController(text: '正确'),
        TextEditingController(text: '错误'),
      ];
    }
    _folderId = widget.question?.folderId;
    // 新建题目默认归入当前所在夹
    if (widget.question == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final qb = context.read<QuestionBankProvider>();
        if (_folderId == null && qb.currentFolderId != null) {
          setState(() => _folderId = qb.currentFolderId);
        }
      });
    }
  }

  @override
  void dispose() {
    _stem.dispose();
    _explanation.dispose();
    _tags.dispose();
    _answer.dispose();
    _source.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: widget.question == null ? '新建题目' : '编辑题目',
        actions: [
          IconButton(
            tooltip: '预览',
            icon: Icon(_preview ? Icons.edit : Icons.visibility),
            onPressed: () => setState(() => _preview = !_preview),
          ),
          if (widget.question != null)
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          IconButton(
            tooltip: '保存',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: FrostedBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 72, 16, 24),
            children: [
              GlassCard(
                padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 题型
                Wrap(
                  spacing: 8,
                  children: QuestionType.values
                      .map((t) => ChoiceChip(
                            label: Text(t.label),
                            selected: _type == t,
                            onSelected: (_) => _changeType(t),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                if (_preview)
                  MarkdownPreview(_stem.text.isEmpty ? '（题干预览）' : _stem.text)
                else
                  TextField(
                    controller: _stem,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: '题干（支持 Markdown）',
                      alignLabelWithHint: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                if (!_preview)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('插入图片'),
                      onPressed: () => _insertImage(_stem),
                    ),
                  ),
                if (!_preview && _stem.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('预览',
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: MarkdownPreview(_stem.text),
                  ),
                ],
                if (!_preview) FormulaBar(controller: _stem),
                const SizedBox(height: 16),
                // 选项（非填空）
                if (_type != QuestionType.fill) _optionsEditor(),
                // 答案
                const SizedBox(height: 16),
                _answerEditor(),
                const SizedBox(height: 16),
                TextField(
                  controller: _explanation,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '解析（支持 Markdown）',
                    alignLabelWithHint: true,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('解析插入图片'),
                    onPressed: () => _insertImage(_explanation),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tags,
                  decoration: const InputDecoration(
                    labelText: '标签（逗号分隔）',
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('难度'),
                    const SizedBox(width: 12),
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        icon: Icon(i <= _difficulty
                            ? Icons.star
                            : Icons.star_border),
                        color: Theme.of(context).colorScheme.tertiary,
                        onPressed: () => setState(() => _difficulty = i),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _source,
                  enabled: widget.question?.sourceAuthorId == null,
                  decoration: InputDecoration(
                    labelText: '出处 / 来源（可选，如教材名·页码·链接）',
                    prefixIcon: const Icon(Icons.link_outlined),
                    hintText: widget.question?.sourceAuthorId != null
                        ? '分享题目，来源沿用原作者'
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                _folderSelector(),
              ],
            ),
          ),
        ],
      ),
          ),
        ),
    );
  }

  void _changeType(QuestionType t) {
    setState(() {
      _type = t;
      if (t == QuestionType.judge) {
        for (final c in _options) {
          c.dispose();
        }
        _options = [
          TextEditingController(text: '正确'),
          TextEditingController(text: '错误'),
        ];
      } else if (t == QuestionType.fill || t == QuestionType.essay) {
        // 无选项
      } else if (_options.length < 2) {
        _options = [TextEditingController(), TextEditingController()];
      }
      _answer.clear();
    });
  }

  Widget _optionsEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('选项', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (var i = 0; i < _options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(String.fromCharCode(65 + i),
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                          fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _options[i],
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '选项 ${String.fromCharCode(65 + i)}',
                    ),
                  ),
                ),
                if (_type != QuestionType.judge)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _options[i].dispose();
                      _options.removeAt(i);
                    }),
                  ),
              ],
            ),
          ),
        if (_type != QuestionType.judge)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('添加选项'),
              onPressed: () =>
                  setState(() => _options.add(TextEditingController())),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _answerEditor() {
    if (_type == QuestionType.essay) {
      return TextField(
        controller: _answer,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: '参考答案 / 评分要点（主观题，考后人工评卷）',
          alignLabelWithHint: true,
        ),
      );
    }
    if (_type == QuestionType.fill) {
      return TextField(
        controller: _answer,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: '答案（多空以 || 分隔，同空多答案以 ||| 分隔）',
          alignLabelWithHint: true,
        ),
      );
    }
    if (_type == QuestionType.judge) {
      return Row(
        children: [
          const Text('正确答案：'),
          const SizedBox(width: 12),
          ChoiceChip(
              label: const Text('正确'),
              selected: _answer.text == '1',
              onSelected: (_) => setState(() => _answer.text = '1')),
          const SizedBox(width: 8),
          ChoiceChip(
              label: const Text('错误'),
              selected: _answer.text == '0',
              onSelected: (_) => setState(() => _answer.text = '0')),
        ],
      );
    }
    // 单选/多选/不定项：从选项中点选
    final multi = _type == QuestionType.multiple ||
        _type == QuestionType.undefined;
    final selectedIdx = _answer.text
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < _options.length; i++)
          FilterChip(
            label: Text(String.fromCharCode(65 + i)),
            selected: selectedIdx.contains(i),
            onSelected: (sel) => setState(() {
              if (multi) {
                if (sel) {
                  selectedIdx.add(i);
                } else {
                  selectedIdx.remove(i);
                }
                _answer.text = (selectedIdx.toList()..sort()).join(',');
              } else {
                _answer.text = sel ? '$i' : '';
              }
            }),
          ),
      ],
    );
  }

  Widget _folderSelector() {
    final qb = context.watch<QuestionBankProvider>();
    return Row(
      children: [
        Icon(Icons.folder_outlined,
            size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        const Text('题库夹'),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButton<String?>(
            value: _folderId,
            isExpanded: true,
            underline: const SizedBox(),
            hint: const Text('根目录（不归档）'),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('根目录（不归档）')),
              ...qb.folders.map((f) => DropdownMenuItem<String?>(
                    value: f.id,
                    child: Text(_folderPathLabel(qb, f),
                        overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (v) => setState(() => _folderId = v),
          ),
        ),
      ],
    );
  }

  String _folderPathLabel(QuestionBankProvider qb, QuestionFolder f) {
    final chain = qb.folderChain(f.parentId);
    final names = chain.map((x) => x.name).join(' / ');
    return names.isEmpty ? f.name : '$names / ${f.name}';
  }

  /// 选择本地图片 → base64 内嵌为 Markdown data URI，插入到给定输入框光标处。
  Future<void> _insertImage(TextEditingController c) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.single.path == null) return;
    final bytes = await File(result.files.single.path!).readAsBytes();
    if (bytes.lengthInBytes > 800 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('图片过大（>800KB），请压缩后再插入以避免题库膨胀')));
      return;
    }
    final ext = result.files.single.extension?.toLowerCase() ?? 'png';
    final mime = ext == 'jpg' ? 'image/jpeg' : 'image/$ext';
    final md = '![图片](data:$mime;base64,${base64Encode(bytes)})';
    final sel = c.selection.isValid ? c.selection.baseOffset : c.text.length;
    final newText =
        c.text.substring(0, sel) + md + c.text.substring(sel);
    c.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel + md.length),
    );
    setState(() {});
  }

  Future<void> _delete() async {    final q = widget.question;
    if (q == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除题目'),
        content: const Text('确认删除这道题目？此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      if (!mounted) return;
      await context.read<QuestionBankProvider>().delete([q.id]);
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _save() async {
    if (_stem.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('题干不能为空')));
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final q = Question(
      id: widget.question?.id ?? '',
      type: _type,
      stem: _stem.text,
      options: _type == QuestionType.fill || _type == QuestionType.essay
          ? const []
          : _options.map((c) => c.text).where((s) => s.isNotEmpty).toList(),
      answer: _answer.text,
      explanation: _explanation.text,
      tags: _tags.text
          .split(RegExp(r'[,，;；\s]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      difficulty: _difficulty,
      sourceNickname: widget.question?.sourceAuthorId != null
          ? widget.question?.sourceNickname
          : (_source.text.trim().isEmpty ? null : _source.text.trim()),
      sourceAuthorId: widget.question?.sourceAuthorId,
      sourceSocial: widget.question?.sourceSocial,
      sourceExportedAt: widget.question?.sourceExportedAt,
      folderId: _folderId,
      createdAt: widget.question?.createdAt ?? now,
      updatedAt: now,
    );
    await context.read<QuestionBankProvider>().save(q);
    if (mounted) Navigator.pop(context, true);
  }
}
