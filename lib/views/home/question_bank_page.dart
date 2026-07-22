import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/models/models.dart';
import '../../core/models/question.dart';
import '../../providers/question_provider.dart';
import '../common/glass.dart';
import 'question_editor_page.dart';
import 'widgets/import_export_dialogs.dart';
import 'widgets/question_tile.dart';

class QuestionBankPage extends StatefulWidget {
  const QuestionBankPage({super.key});
  @override
  State<QuestionBankPage> createState() => _QuestionBankPageState();
}

class _QuestionBankPageState extends State<QuestionBankPage> {
  final _search = TextEditingController();
  final Set<String> _selected = {};
  bool _selectMode = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qb = context.watch<QuestionBankProvider>();
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            // 顶部搜索 + 操作
            GlassCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.library_books_outlined),
                      const SizedBox(width: 8),
                      Text('题库管理',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        tooltip: '导入',
                        icon: const Icon(Icons.file_download_outlined),
                        onPressed: () => showImportDialog(context),
                      ),
                      IconButton(
                        tooltip: '导出',
                        icon: const Icon(Icons.ios_share),
                        onPressed: () => showExportQuestionsDialog(context,
                            questions: qb.questions),
                      ),
                      IconButton(
                        tooltip: _selectMode ? '退出选择' : '批量选择',
                        icon: Icon(_selectMode
                            ? Icons.close
                            : Icons.checklist_rtl_outlined),
                        onPressed: qb.questions.isEmpty
                            ? null
                            : () => setState(() {
                                  _selectMode = !_selectMode;
                                  if (!_selectMode) _selected.clear();
                                }),
                      ),
                      IconButton(
                        tooltip: '新建题目',
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => _edit(context, null),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: '搜索题干、解析…',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _search.clear();
                                qb.setKeyword('');
                              }),
                    ),
                    onChanged: qb.setKeyword,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 文件夹导航
            _folderNav(context, qb),
            const SizedBox(height: 8),
            // 筛选条
            _filterBar(context, qb),
            const SizedBox(height: 8),
            // 选择模式操作栏
            if (_selectMode || _selected.isNotEmpty)
              _selectionBar(context, qb),
            // 列表
            Expanded(
              child: qb.questions.isEmpty
                  ? EmptyState(
                      icon: Icons.inbox_outlined,
                      title: '题库为空',
                      subtitle: '点击右上角新建题目，或从文件批量导入',
                      action: FilledButton.icon(
                        onPressed: () => _edit(context, null),
                        icon: const Icon(Icons.add),
                        label: const Text('新建题目'),
                      ),
                    )
                  : ListView.builder(
                      itemCount: qb.questions.length,
                      itemBuilder: (_, i) {
                        final q = qb.questions[i];
                        final sel = _selected.contains(q.id);
                        return QuestionTile(
                          question: q,
                          selected: sel,
                          selectionMode: _selectMode || _selected.isNotEmpty,
                          onTap: () {
                            if (_selectMode || _selected.isNotEmpty) {
                              _toggle(q.id);
                            } else {
                              _edit(context, q);
                            }
                          },
                          onLongPress: () => setState(() {
                            _selectMode = true;
                            _toggle(q.id);
                          }),
                          onAiExplain: () => _aiExplain(context, q),
                          onDelete: () => _deleteSingle(context, q),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _deleteSingle(BuildContext context, Question q) async {
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
      if (!context.mounted) return;
      await context.read<QuestionBankProvider>().delete([q.id]);
    }
  }

  Widget _selectionBar(BuildContext context, QuestionBankProvider qb) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text('已选 ${_selected.length} 项'),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: () => setState(() {
                  if (qb.questions.isNotEmpty &&
                      _selected.length == qb.questions.length) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(qb.questions.map((q) => q.id));
                  }
                }),
                icon: const Icon(Icons.select_all, size: 18),
                label: Text(qb.questions.isNotEmpty &&
                        _selected.length == qb.questions.length
                    ? '取消全选'
                    : '全选'),
              ),
              TextButton.icon(
                onPressed: () => _moveSelected(context, qb),
                icon: const Icon(Icons.drive_file_move_outline, size: 18),
                label: const Text('移入夹'),
              ),
              TextButton.icon(
                onPressed: () => _setTagsSelected(context, qb),
                icon: const Icon(Icons.label_outline, size: 18),
                label: const Text('标签'),
              ),
              TextButton.icon(
                onPressed: () => _setDifficultySelected(context, qb),
                icon: const Icon(Icons.star_outline, size: 18),
                label: const Text('难度'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _selectMode = false;
                  _selected.clear();
                }),
                child: const Text('退出'),
              ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除题目'),
                    content: Text('确认删除 ${_selected.length} 道题目？'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('删除')),
                    ],
                  ),
                );
                if (ok == true) {
                  await qb.delete(_selected.toList());
                  _selected.clear();
                }
              },
              child: const Text('删除'),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _filterBar(BuildContext context, QuestionBankProvider qb) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final t in QuestionType.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(t.label),
                selected: qb.typeFilter.contains(t),
                onSelected: (_) => qb.toggleType(t),
              ),
            ),
          if (qb.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8),
              child: VerticalDivider(
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant),
            ),
          for (final tag in qb.tags.take(12))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text('#$tag'),
                selected: qb.tagFilter.contains(tag),
                onSelected: (_) => qb.toggleTag(tag),
              ),
            ),
          if (qb.sources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: PopupMenuButton<String>(
                tooltip: '按来源筛选',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: qb.sourceFilter != null
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.account_circle, size: 16),
                      const SizedBox(width: 4),
                      Text(qb.sourceFilter ?? '来源'),
                    ],
                  ),
                ),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: '', child: Text('全部')),
                  ...qb.sources.map((s) =>
                      PopupMenuItem(value: s, child: Text(s))),
                ],
                onSelected: (v) => qb.setSource(v.isEmpty ? null : v),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilterChip(
              label: const Text('仅薄弱'),
              selected: qb.weakOnly,
              onSelected: (_) => qb.setWeakOnly(!qb.weakOnly),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: PopupMenuButton<QuestionSortBy>(
              tooltip: '排序',
              onSelected: qb.setSort,
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: QuestionSortBy.updatedDesc, child: Text('最近更新')),
                PopupMenuItem(
                    value: QuestionSortBy.createdDesc, child: Text('最近创建')),
                PopupMenuItem(
                    value: QuestionSortBy.difficultyDesc, child: Text('难度优先')),
                PopupMenuItem(
                    value: QuestionSortBy.accuracyAsc, child: Text('正确率升序')),
                PopupMenuItem(
                    value: QuestionSortBy.practicedAsc, child: Text('最久未练')),
                PopupMenuItem(
                    value: QuestionSortBy.practicedDesc, child: Text('最近练习')),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.sort, size: 16),
                  const SizedBox(width: 4),
                  Text(_sortLabel(qb.sortBy)),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _sortLabel(QuestionSortBy s) {
    switch (s) {
      case QuestionSortBy.updatedDesc:
        return '最近更新';
      case QuestionSortBy.createdDesc:
        return '最近创建';
      case QuestionSortBy.difficultyDesc:
        return '难度优先';
      case QuestionSortBy.accuracyAsc:
        return '正确率升序';
      case QuestionSortBy.practicedAsc:
        return '最久未练';
      case QuestionSortBy.practicedDesc:
        return '最近练习';
    }
  }

  Future<void> _edit(BuildContext context, Question? q) async {
    final refresh = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QuestionEditorPage(question: q),
      ),
    );
    if (refresh == true && context.mounted) {
      context.read<QuestionBankProvider>().load();
    }
  }

  void _aiExplain(BuildContext context, Question q) {
    // 跳转到 AI 模块并预填提示词
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请在 AI 模块选择服务后粘贴题目进行解释')),
    );
  }

  // ============ 题库夹导航 ============
  Widget _folderNav(BuildContext context, QuestionBankProvider qb) {
    final chain = qb.folderChain(qb.currentFolderId);
    final children = qb.childFolders(qb.currentFolderId);
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_open, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: qb.currentFolderId == null
                            ? null
                            : () => qb.enterFolder(null),
                        child: const Text('全部题目'),
                      ),
                      for (final f in chain) ...[
                        Icon(Icons.chevron_right,
                            size: 16, color: cs.onSurfaceVariant),
                        TextButton(
                          onPressed: qb.currentFolderId == f.id
                              ? null
                              : () => qb.enterFolder(f.id),
                          child: Text(f.name),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: '新建子文件夹',
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                onPressed: () => _createFolder(context, qb),
              ),
            ],
          ),
          if (children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in children) _folderChip(context, qb, f),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _folderChip(
      BuildContext context, QuestionBankProvider qb, QuestionFolder f) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => qb.enterFolder(f.id),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.folder, size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(f.name),
                  const SizedBox(width: 4),
                  Text('${qb.questionCountIn(f.id)}',
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 16),
            tooltip: '文件夹操作',
            onSelected: (v) {
              if (v == 'rename') _renameFolder(context, qb, f);
              if (v == 'delete') _deleteFolder(context, qb, f);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('重命名')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }

  String _folderPathLabel(QuestionBankProvider qb, QuestionFolder f) {
    final chain = qb.folderChain(f.parentId);
    final names = chain.map((x) => x.name).join(' / ');
    return names.isEmpty ? f.name : '$names / ${f.name}';
  }

  void _createFolder(BuildContext context, QuestionBankProvider qb) {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: '名称')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await qb.createFolder(
                  name: c.text, parentId: qb.currentFolderId);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _renameFolder(
      BuildContext context, QuestionBankProvider qb, QuestionFolder f) {
    final c = TextEditingController(text: f.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await qb.renameFolder(f.id, c.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _deleteFolder(
      BuildContext context, QuestionBankProvider qb, QuestionFolder f) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件夹'),
        content: Text('删除「${f.name}」？夹内题目与子文件夹将移到上一级。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await qb.deleteFolder(f.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _moveSelected(BuildContext context, QuestionBankProvider qb) {
    showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('移入文件夹'),
        children: [
          SimpleDialogOption(
            child: const Text('根目录（不归档）'),
            onPressed: () => Navigator.pop(ctx, ''),
          ),
          for (final f in qb.folders)
            SimpleDialogOption(
              child: Text(_folderPathLabel(qb, f)),
              onPressed: () => Navigator.pop(ctx, f.id),
            ),
        ],
      ),
    ).then((targetId) async {
      if (targetId == null) return;
      await qb.moveQuestionsToFolder(
          _selected.toList(), targetId.isEmpty ? null : targetId);
      if (!mounted) return;
      setState(_selected.clear);
    });
  }

  void _setTagsSelected(BuildContext context, QuestionBankProvider qb) {
    final c = TextEditingController();
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量添加标签'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '为选中题目追加标签（逗号分隔）',
            hintText: '如：重点、第一章',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('添加')),
        ],
      ),
    ).then((ok) async {
      if (ok != true) return;
      final tags = c.text
          .split(RegExp(r'[,，;；\s]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (tags.isEmpty) return;
      await qb.setTagsFor(_selected.toList(), tags);
      if (!mounted) return;
      setState(_selected.clear);
    });
  }

  void _setDifficultySelected(BuildContext context, QuestionBankProvider qb) {
    showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('批量设置难度'),
        children: [
          for (var i = 1; i <= 5; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, i),
              child: Row(children: [
                for (var j = 1; j <= 5; j++)
                  Icon(j <= i ? Icons.star : Icons.star_border,
                      size: 18, color: Theme.of(context).colorScheme.tertiary),
                const SizedBox(width: 8),
                Text('$i 星'),
              ]),
            ),
        ],
      ),
    ).then((level) async {
      if (level == null) return;
      await qb.setDifficultyFor(_selected.toList(), level);
      if (!mounted) return;
      setState(_selected.clear);
    });
  }
}
