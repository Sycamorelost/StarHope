import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/models/models.dart';
import '../../core/models/question.dart';
import '../../providers/auth_provider.dart';
import '../../providers/practice_exam_provider.dart';
import '../../services/database/database.dart';
import '../../services/export_service.dart';
import '../common/glass.dart';
import 'practice_page.dart';
import 'widgets/question_tile.dart';

/// 错题本 -- 侧边栏顶级菜单，与题库同级
class WrongBookPage extends StatefulWidget {
  const WrongBookPage({super.key});
  @override
  State<WrongBookPage> createState() => _WrongBookPageState();
}

class _WrongBookPageState extends State<WrongBookPage> {
  List<WrongQuestion> _wrong = [];
  Map<String, Question> _map = {};
  List<WrongGroup> _groups = [];
  // _filteredSorted 的 memo 缓存（按输入签名命中）
  String? _fsKey;
  List<WrongQuestion>? _fsCache;
  String _sort = 'time'; // time / count / mastery
  // 分类筛选
  List<String> _allTags = [];
  List<String> _allSources = [];
  List<String> _usedGroups = []; // 错题里已用过的分组名
  List<String> _tagFilter = [];
  List<QuestionType> _typeFilter = [];
  String? _sourceFilter;
  List<int> _masteryFilter = []; // 0未掌握/1复习中/2已掌握 多选
  String? _groupFilter; // null=全部, ''=未分组, 其他=分组名
  List<({String type, String name})> _sessions = []; // 答题来源场次
  String? _sessionFilter; // "$type|$name"，null=全部
  bool _selectMode = false; // 多选模式（批量练错题）
  final Set<String> _selected = {}; // 选中的 questionId

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pe = context.read<PracticeExamProvider>();
    final wrong = await pe.wrongList();
    final groups = await pe.wrongGroups();
    final qids = wrong.map((w) => w.questionId).toSet();
    final all = await AppDatabase.instance.allQuestions();
    final map = {for (final q in all) if (qids.contains(q.id)) q.id: q};
    final tags = <String>{};
    final sources = <String>{};
    for (final q in map.values) {
      tags.addAll(q.tags);
      if (q.sourceNickname != null && q.sourceNickname!.isNotEmpty) {
        sources.add(q.sourceNickname!);
      }
    }
    final used = <String>{};
    final sessions = <({String type, String name})>{};
    for (final w in wrong) {
      if (w.customGroup != null && w.customGroup!.isNotEmpty) {
        used.add(w.customGroup!);
      }
      final t = w.sourceSessionType;
      final n = w.sourceSessionName;
      if (t != null && t.isNotEmpty && n != null && n.isNotEmpty) {
        sessions.add((type: t, name: n));
      }
    }
    setState(() {
      _wrong = wrong;
      _map = map;
      _groups = groups;
      _allTags = tags.toList()..sort();
      _allSources = sources.toList()..sort();
      _usedGroups = used.toList()..sort();
      _sessions = sessions.toList();
    });
  }

  /// 经分类筛选后的错题（按输入签名 memo：数据按身份、筛选按值；输入不变则复用上次结果，
  /// 避免每次 rebuild 全量 where+sort）。
  List<WrongQuestion> get _filteredSorted {
    final key = '${identityHashCode(_wrong)}|${identityHashCode(_map)}|'
        '$_sort|${_typeFilter.join(',')}|${_tagFilter.join(',')}|'
        '$_sourceFilter|${_masteryFilter.join(',')}|$_groupFilter|$_sessionFilter';
    if (_fsKey == key && _fsCache != null) return _fsCache!;
    _fsKey = key;
    _fsCache = _computeFiltered();
    return _fsCache!;
  }

  List<WrongQuestion> _computeFiltered() {
    var list = _wrong.where((w) {
      final q = _map[w.questionId];
      if (q == null) return false;
      if (_typeFilter.isNotEmpty && !_typeFilter.contains(q.type)) return false;
      if (_tagFilter.isNotEmpty && !_tagFilter.any((t) => q.tags.contains(t))) {
        return false;
      }
      if (_sourceFilter != null && q.sourceNickname != _sourceFilter) {
        return false;
      }
      if (_masteryFilter.isNotEmpty && !_masteryFilter.contains(w.mastery)) {
        return false;
      }
      if (_groupFilter != null) {
        final g = w.customGroup;
        if (_groupFilter == '') {
          if (g != null && g.isNotEmpty) return false;
        } else if (g != _groupFilter) {
          return false;
        }
      }
      if (_sessionFilter != null) {
        final sep = _sessionFilter!.indexOf('|');
        final t = sep >= 0 ? _sessionFilter!.substring(0, sep) : '';
        final n = sep >= 0 ? _sessionFilter!.substring(sep + 1) : '';
        if (w.sourceSessionType != t || w.sourceSessionName != n) return false;
      }
      return true;
    }).toList();
    if (_sort == 'count') {
      list.sort((a, b) => b.wrongCount.compareTo(a.wrongCount));
    } else if (_sort == 'mastery') {
      list.sort((a, b) => a.mastery.compareTo(b.mastery));
    } else {
      list.sort((a, b) => b.lastWrongAt.compareTo(a.lastWrongAt));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredSorted;
    final hasFilter = _tagFilter.isNotEmpty ||
        _typeFilter.isNotEmpty ||
        _sourceFilter != null ||
        _masteryFilter.isNotEmpty ||
        _groupFilter != null ||
        _sessionFilter != null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, size: 28),
                const SizedBox(width: 8),
                Text('错题本',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Chip(
                  label: Text('${list.length} 题',
                      style: const TextStyle(fontSize: 12)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                IconButton(
                  tooltip: '导出错题',
                  icon: const Icon(Icons.ios_share),
                  onPressed: list.isEmpty ? null : () => _exportWrong(context, list),
                ),
                IconButton(
                  tooltip: _selectMode ? '退出选择' : '批量选择',
                  icon: Icon(_selectMode
                      ? Icons.close
                      : Icons.checklist_rtl_outlined),
                  onPressed: list.isEmpty
                      ? null
                      : () => setState(() {
                            _selectMode = !_selectMode;
                            if (!_selectMode) _selected.clear();
                          }),
                ),
                if (hasFilter)
                  TextButton.icon(
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: const Text('清除筛选'),
                    onPressed: () => setState(() {
                      _tagFilter = [];
                      _typeFilter = [];
                      _sourceFilter = null;
                      _masteryFilter = [];
                      _groupFilter = null;
                      _sessionFilter = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_selectMode || _selected.isNotEmpty)
              _wrongSelectionBar(context, list),
            // 分类筛选条
            if (_wrong.isNotEmpty) _filterBar(context),
            Row(
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'time', label: Text('按时间')),
                    ButtonSegment(value: 'count', label: Text('按次数')),
                    ButtonSegment(value: 'mastery', label: Text('按掌握度')),
                  ],
                  selected: {_sort},
                  onSelectionChanged: (s) => setState(() => _sort = s.first),
                ),
                const Spacer(),
                if (list.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('清空'),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('清空错题本'),
                          content: const Text('确认清空全部错题记录？题目本身不会被删除。'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消')),
                            FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('清空')),
                          ],
                        ),
                      );
                      if (!context.mounted) return;
                      if (ok == true) {
                        for (final w in list) {
                          await context
                              .read<PracticeExamProvider>()
                              .clearWrong(w.questionId);
                        }
                        await _load();
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(
                      icon: Icons.check_circle_outline,
                      title: '错题本为空',
                      subtitle: '练习或考试中的错题会自动加入这里',
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final w = list[i];
                        final q = _map[w.questionId];
                        if (q == null) return const SizedBox.shrink();
                        return _wrongTile(context, w, q);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wrongSelectionBar(BuildContext context, List<WrongQuestion> list) {
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
                  if (_selected.length == list.length) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(list.map((w) => w.questionId));
                  }
                }),
                icon: const Icon(Icons.select_all, size: 18),
                label: Text(
                    _selected.length == list.length ? '取消全选' : '全选'),
              ),
              TextButton.icon(
                onPressed: _selected.isEmpty
                    ? null
                    : () => _practiceSelected(context),
                icon: const Icon(Icons.fitness_center_outlined, size: 18),
                label: const Text('练这些错题'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _selectMode = false;
                  _selected.clear();
                }),
                child: const Text('退出'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _practiceSelected(BuildContext context) async {
    final questions = _wrong
        .where((w) => _selected.contains(w.questionId))
        .map((w) => _map[w.questionId])
        .whereType<Question>()
        .toList();
    if (questions.isEmpty) return;
    final pe = context.read<PracticeExamProvider>();
    await pe.startPractice(questions, filter: const QuestionFilter());
    if (!mounted) return;
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
    if (!context.mounted) return;
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const PracticePage()));
  }

  /// 分类筛选条：掌握度 / 分组 / 题型 / 标签 / 来源
  Widget _filterBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            // 掌握度
            for (final m in const [0, 1, 2])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(_masteryLabel(m)),
                  avatar:
                      CircleAvatar(backgroundColor: _masteryColor(m), radius: 5),
                  selected: _masteryFilter.contains(m),
                  onSelected: (_) => setState(() {
                    if (_masteryFilter.contains(m)) {
                      _masteryFilter =
                          _masteryFilter.where((e) => e != m).toList();
                    } else {
                      _masteryFilter = [..._masteryFilter, m];
                    }
                  }),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: VerticalDivider(
                  width: 1, color: cs.outlineVariant),
            ),
            // 分组
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PopupMenuButton<String>(
                tooltip: '按分组筛选',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _groupFilter != null
                        ? cs.primaryContainer
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.folder_outlined, size: 16),
                      const SizedBox(width: 4),
                      Text(_groupFilter == null
                          ? '分组'
                          : (_groupFilter == '' ? '未分组' : _groupFilter!)),
                    ],
                  ),
                ),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: '', child: Text('未分组')),
                  ..._allGroupNames()
                      .map((g) => PopupMenuItem(value: g, child: Text(g))),
                ],
                onSelected: (v) =>
                    setState(() => _groupFilter = _groupFilter == v ? null : v),
              ),
            ),
            IconButton(
              tooltip: '管理分组',
              icon: const Icon(Icons.label_outline, size: 20),
              onPressed: () => _manageGroups(context),
              visualDensity: VisualDensity.compact,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: VerticalDivider(
                  width: 1, color: cs.outlineVariant),
            ),
            // 题型
            for (final t in QuestionType.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(t.label),
                  selected: _typeFilter.contains(t),
                  onSelected: (_) => setState(() {
                    if (_typeFilter.contains(t)) {
                      _typeFilter = _typeFilter.where((e) => e != t).toList();
                    } else {
                      _typeFilter = [..._typeFilter, t];
                    }
                  }),
                ),
              ),
            if (_allTags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 8),
                child: VerticalDivider(
                    width: 1, color: cs.outlineVariant),
              ),
            for (final tag in _allTags)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text('#$tag'),
                  selected: _tagFilter.contains(tag),
                  onSelected: (_) => setState(() {
                    if (_tagFilter.contains(tag)) {
                      _tagFilter = _tagFilter.where((e) => e != tag).toList();
                    } else {
                      _tagFilter = [..._tagFilter, tag];
                    }
                  }),
                ),
              ),
            if (_allSources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: PopupMenuButton<String>(
                  tooltip: '按来源筛选',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _sourceFilter != null
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.account_circle, size: 16),
                        const SizedBox(width: 4),
                        Text(_sourceFilter ?? '来源'),
                      ],
                    ),
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: '', child: Text('全部')),
                    ..._allSources
                        .map((s) => PopupMenuItem(value: s, child: Text(s))),
                  ],
                  onSelected: (v) =>
                      setState(() => _sourceFilter = v.isEmpty ? null : v),
                ),
              ),
            if (_sessions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: PopupMenuButton<String>(
                  tooltip: '按场次筛选',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _sessionFilter != null
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.history_edu_outlined, size: 16),
                        const SizedBox(width: 4),
                        Text(_sessionFilter == null
                            ? '场次'
                            : _sessionLabel(_sessionFilter!)),
                      ],
                    ),
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: '', child: Text('全部')),
                    ..._sessions.map((s) => PopupMenuItem(
                          value: '${s.type}|${s.name}',
                          child: Text(_sessionLabel('${s.type}|${s.name}')),
                        )),
                  ],
                  onSelected: (v) => setState(
                      () => _sessionFilter = v.isEmpty ? null : v),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 分组名集合（已建分组 + 错题里已用过的）
  List<String> _allGroupNames() {
    final set = <String>{};
    for (final g in _groups) {
      set.add(g.name);
    }
    for (final g in _usedGroups) {
      set.add(g);
    }
    return set.toList()..sort();
  }

  String _masteryLabel(int m) => const ['未掌握', '复习中', '已掌握'][m];

  String _sessionLabel(String key) {
    final sep = key.indexOf('|');
    final t = sep >= 0 ? key.substring(0, sep) : '';
    final n = sep >= 0 ? key.substring(sep + 1) : key;
    const labels = {'exam': '考试', 'practice': '练习', 'quick': '快练'};
    return '[${labels[t] ?? t}] $n';
  }
  Color _masteryColor(int m) =>
      const [Colors.red, Colors.orange, Colors.green][m];

  Widget _wrongTile(BuildContext context, WrongQuestion w, Question q) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        onTap: () {
          if (_selectMode) {
            setState(() {
              if (_selected.contains(q.id)) {
                _selected.remove(q.id);
              } else {
                _selected.add(q.id);
              }
            });
          } else {
            _showDetail(context, w, q);
          }
        },
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectMode)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: Icon(
                  _selected.contains(q.id)
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: _selected.contains(q.id) ? cs.primary : cs.outline,
                ),
              ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: _masteryColor(w.mastery).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                w.mastery == 2
                    ? '已掌握'
                    : (w.consecutiveCorrect > 0
                        ? '连对 ${w.consecutiveCorrect}'
                        : '错 ${w.wrongCount}'),
                style: TextStyle(
                    fontSize: 11,
                    color: _masteryColor(w.mastery),
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _typeChip(context, q.type),
                      const SizedBox(width: 6),
                      if (w.customGroup != null && w.customGroup!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(w.customGroup!,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSecondaryContainer)),
                        ),
                      const SizedBox(width: 6),
                      if (q.isFromShare)
                        SourceBadge(
                            nickname: q.sourceNickname,
                            authorId: q.sourceAuthorId),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(q.stem.isEmpty ? '（无题干）' : q.stem,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.4)),
                  const SizedBox(height: 4),
                  Text(
                    '${w.lastPracticedAt != null ? "最近练习：${_fmt(w.lastPracticedAt!)}" : "最近答错：${_fmt(w.lastWrongAt)}"}'
                    '${q.practiceCount > 0 ? " · 正确率 ${(q.correctCount / q.practiceCount * 100).round()}%(${q.practiceCount}次)" : ""}',
                    style:
                        TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'detail', child: Text('查看详情')),
                PopupMenuItem(value: 'repractice', child: Text('重练本题')),
                PopupMenuItem(value: 'mastery', child: Text('标记掌握度')),
                PopupMenuItem(value: 'group', child: Text('移动到分组')),
                PopupMenuItem(value: 'clear', child: Text('移出错题本')),
              ],
              onSelected: (v) async {
                if (v == 'detail') {
                  _showDetail(context, w, q);
                } else if (v == 'repractice') {
                  _quickPractice(context, w, q);
                } else if (v == 'mastery') {
                  _pickMastery(context, w);
                } else if (v == 'group') {
                  _pickGroup(context, w);
                } else if (v == 'clear') {
                  await context.read<PracticeExamProvider>().clearWrong(q.id);
                  await _load();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, WrongQuestion w, Question q) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            _typeChip(ctx, q.type),
            const SizedBox(width: 8),
            if (q.isFromShare)
              SourceBadge(nickname: q.sourceNickname, authorId: q.sourceAuthorId),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _masteryColor(w.mastery).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_masteryLabel(w.mastery),
                  style: TextStyle(
                      fontSize: 11, color: _masteryColor(w.mastery))),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MarkdownPreview(q.stem, selectable: true),
                const SizedBox(height: 12),
                if (q.options.isNotEmpty) ...[
                  for (var i = 0; i < q.options.length; i++)
                    Text('${String.fromCharCode(65 + i)}. ${q.options[i]}',
                        style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                ],
                Text('正确答案：${_answerDisplay(q)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                    '累计答错 ${w.wrongCount} 次 · 连续答对 ${w.consecutiveCorrect} 次',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                if (q.explanation.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('解析', style: TextStyle(fontWeight: FontWeight.bold)),
                  MarkdownPreview(q.explanation, selectable: true),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.school_outlined, size: 18),
            label: const Text('掌握度'),
            onPressed: () {
              Navigator.pop(ctx);
              _pickMastery(context, w);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.folder_outlined, size: 18),
            label: const Text('分组'),
            onPressed: () {
              Navigator.pop(ctx);
              _pickGroup(context, w);
            },
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _pickMastery(BuildContext context, WrongQuestion w) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('标记掌握度'),
        children: [
          for (final m in const [0, 1, 2])
            SimpleDialogOption(
              child: Row(children: [
                Icon(Icons.circle, size: 12, color: _masteryColor(m)),
                const SizedBox(width: 8),
                Text(_masteryLabel(m)),
              ]),
              onPressed: () async {
                await context
                    .read<PracticeExamProvider>()
                    .setMastery(w.questionId, m);
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              },
            ),
        ],
      ),
    );
  }

  void _pickGroup(BuildContext context, WrongQuestion w) {
    final names = _allGroupNames();
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('移动到分组'),
        children: [
          SimpleDialogOption(
            child: const Text('移出分组（未分组）'),
            onPressed: () async {
              await context
                  .read<PracticeExamProvider>()
                  .setWrongGroup(w.questionId, null);
              if (ctx.mounted) Navigator.pop(ctx);
              await _load();
            },
          ),
          for (final g in names)
            SimpleDialogOption(
              child: Text(g),
              onPressed: () async {
                await context
                    .read<PracticeExamProvider>()
                    .setWrongGroup(w.questionId, g);
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              },
            ),
          SimpleDialogOption(
            child: const Text('+ 新建分组…'),
            onPressed: () {
              Navigator.pop(ctx);
              _createGroup(context, thenMove: w);
            },
          ),
        ],
      ),
    );
  }

  void _createGroup(BuildContext context, {WrongQuestion? thenMove}) {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: '分组名')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final name = c.text.trim();
              if (name.isEmpty) return;
              final g = WrongGroup(
                id: CryptoService.generateId(),
                name: name,
                createdAt: DateTime.now().millisecondsSinceEpoch,
              );
              final pe = context.read<PracticeExamProvider>();
              await pe.saveWrongGroup(g);
              if (thenMove != null) {
                await pe.setWrongGroup(thenMove.questionId, name);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              await _load();
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _manageGroups(BuildContext context) {
    final pe = context.read<PracticeExamProvider>();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('错题分组管理')),
            if (_groups.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无分组', style: TextStyle(fontSize: 13)),
              ),
            for (final g in _groups)
              ListTile(
                leading: const Icon(Icons.label_outline),
                title: Text(g.name),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () async {
                    await pe.deleteWrongGroup(g.id);
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                  },
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新建分组'),
              onTap: () {
                Navigator.pop(ctx);
                _createGroup(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 单题快练（错题本内就地重练，含判题与降权）
  void _quickPractice(BuildContext context, WrongQuestion w, Question q) {
    String answer = '';
    bool submitted = false;
    bool correct = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (sctx, set) {
          Widget input;
          if (q.type == QuestionType.essay) {
            input = TextField(
              enabled: !submitted,
              maxLines: 5,
              decoration: const InputDecoration(labelText: '输入答案（主观题）'),
              onChanged: (v) => answer = v,
            );
          } else if (q.type == QuestionType.fill) {
            input = TextField(
              enabled: !submitted,
              decoration: const InputDecoration(labelText: '输入答案'),
              onChanged: (v) => answer = v,
            );
          } else if (q.type == QuestionType.judge) {
            input = Row(
              children: [
                Expanded(
                    child: _judgeBtn(sctx, '正确', answer == '1', submitted,
                        () => set(() => answer = '1'))),
                const SizedBox(width: 8),
                Expanded(
                    child: _judgeBtn(sctx, '错误', answer == '0', submitted,
                        () => set(() => answer = '0'))),
              ],
            );
          } else {
            final multi = q.type == QuestionType.multiple ||
                q.type == QuestionType.undefined;
            final sel = answer
                .split(',')
                .map((s) => int.tryParse(s.trim()))
                .whereType<int>()
                .toSet();
            input = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < q.options.length; i++)
                  FilterChip(
                    label: Text(
                        '${String.fromCharCode(65 + i)}. ${q.options[i]}'),
                    selected: sel.contains(i),
                    onSelected: submitted
                        ? null
                        : (v) => set(() {
                              if (multi) {
                                if (v) {
                                  sel.add(i);
                                } else {
                                  sel.remove(i);
                                }
                                answer = (sel.toList()..sort()).join(',');
                              } else {
                                answer = '$i';
                              }
                            }),
                  ),
              ],
            );
          }
          return AlertDialog(
            title: Text(submitted ? (correct ? '回答正确' : '回答错误') : '重练本题'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _typeChip(sctx, q.type),
                    const SizedBox(height: 8),
                    MarkdownPreview(q.stem, selectable: true),
                    const SizedBox(height: 12),
                    input,
                    if (submitted) ...[
                      const SizedBox(height: 12),
                      Text('正确答案：${_answerDisplay(q)}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (correct)
                        const Text('连续答对达标后将自动移出错题本。',
                            style:
                                TextStyle(fontSize: 12, color: Colors.green)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              if (!submitted)
                FilledButton(
                  onPressed: answer.isEmpty
                      ? null
                      : () async {
                          final ok = Grader.judge(q, answer);
                          final now = DateTime.now().millisecondsSinceEpoch;
                          if (ok) {
                            await AppDatabase.instance.recordCorrect(q.id, now);
                          } else {
                            await AppDatabase.instance.recordWrong(q.id, now,
                                sourceSessionType: 'quick',
                                sourceSessionName: '错题本快练');
                          }
                          set(() {
                            submitted = true;
                            correct = ok;
                          });
                        },
                  child: const Text('提交'),
                ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(sctx);
                  await _load();
                },
                child: Text(submitted ? '关闭' : '取消'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _judgeBtn(
      BuildContext ctx, String label, bool selected, bool disabled, VoidCallback onTap) {
    final cs = Theme.of(ctx).colorScheme;
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
        ),
        child: Text(label),
      ),
    );
  }

  Future<void> _exportWrong(
      BuildContext context, List<WrongQuestion> wrongs) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final export = ExportService();
    final meta = export.buildMeta(user, ShareContentType.questionBank);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出错题',
      fileName: 'wrong_questions.starhope',
      type: FileType.custom,
      allowedExtensions: const ['starhope'],
    );
    if (path == null) return;
    final questions = wrongs
        .map((w) => _map[w.questionId])
        .whereType<Question>()
        .toList();
    await export.exportWrongQuestions(
        path: path, wrongs: wrongs, questions: questions, meta: meta);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出 ${wrongs.length} 道错题')));
  }

  String _answerDisplay(Question q) {
    if (q.type == QuestionType.fill) return q.answer;
    if (q.type == QuestionType.essay) return q.answer;
    if (q.type == QuestionType.judge) return q.answer == '1' ? '正确' : '错误';
    return q.answer
        .split(',')
        .map((i) {
          final idx = int.tryParse(i);
          return idx != null && idx < q.options.length
              ? String.fromCharCode(65 + idx)
              : '?';
        })
        .join(',');
  }

  String _fmt(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms).toString().substring(0, 16);

  Widget _typeChip(BuildContext context, QuestionType t) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: cs.primaryContainer, borderRadius: BorderRadius.circular(6)),
      child: Text(t.label,
          style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer)),
    );
  }
}

// 引用常量
// ignore: unused_element
const String _kApp = AppConstants.appName;
