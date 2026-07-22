import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/models/models.dart';
import '../../core/models/question.dart';
import '../../providers/auth_provider.dart';
import '../../providers/practice_exam_provider.dart';
import '../../providers/question_provider.dart';
import '../../services/database/database.dart';
import '../../services/export_service.dart';
import '../common/glass.dart';
import 'practice_page.dart';
import 'widgets/answer_card_dialog.dart';
import 'widgets/import_export_dialogs.dart';
import 'widgets/answer_widgets.dart';
import 'widgets/question_picker.dart';
import 'widgets/question_tile.dart';

class ExamPage extends StatefulWidget {
  const ExamPage({super.key});
  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  @override
  Widget build(BuildContext context) {
    final pe = context.watch<PracticeExamProvider>();
    if (pe.inExam) return _examRunning(context, pe);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Row(
              children: [
                Text('考试',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  tooltip: '导出考试',
                  icon: const Icon(Icons.ios_share),
                  onPressed:
                      pe.rules.isEmpty ? null : () => _exportExam(context, pe),
                ),
                IconButton(
                  tooltip: '导入考试',
                  icon: const Icon(Icons.file_download_outlined),
                  onPressed: () => _importExam(context, pe),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _editRule(context, null),
                  icon: const Icon(Icons.add),
                  label: const Text('新建规则'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('考试规则', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (pe.rules.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无考试规则，请新建。'),
              ),
            for (final r in pe.rules) _ruleCard(context, pe, r),
            const SizedBox(height: 24),
            Text('成绩单', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (pe.results.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无考试记录。'),
              ),
            for (final res in pe.results) _resultCard(context, res),
          ],
        ),
      ),
    );
  }

  Widget _ruleCard(BuildContext context, PracticeExamProvider pe, ExamRule r) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(r.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              PopupMenuButton<String>(
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  const PopupMenuItem(value: 'del', child: Text('删除')),
                ],
                onSelected: (v) {
                  if (v == 'edit') {
                    _editRule(context, r);
                  } else if (v == 'del') {
                    pe.deleteRule(r.id);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
              '${r.effectiveCount} 题${r.hasTypeQuotas ? "(配额)" : (r.isPinned ? "(自选)" : "")} · ${r.durationMinutes} 分钟 · 满分 ${r.totalScore} · 及格 ${(r.passRate * 100).round()}% · ${r.allowReviewBack ? "允许回看" : "禁止回看"}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _startExam(context, pe, r),
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始考试'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(BuildContext context, ExamResult r) {
    final passRate = r.totalScore > 0 ? r.score / r.totalScore : 0.0;
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_turned_in, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(r.ruleName,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              _passBadge(context, r),
              const SizedBox(width: 8),
              Text('${r.score}/${r.totalScore}',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.primary)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
              '正确 ${r.correctCount} · 错误 ${r.wrongCount} · 用时 ${((r.submittedAt - r.startedAt) ~/ 60000)} 分钟',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 6),
          _scoreBreakdown(context, r),
          if (r.focusLostCount > 0 || r.timeAnomaly || r.autoSubmitted) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                if (r.focusLostCount > 0)
                  _warnChip('失焦 ${r.focusLostCount} 次'),
                if (r.timeAnomaly) _warnChip('系统时间异常'),
                if (r.autoSubmitted) _warnChip('超时自动交卷'),
              ],
            ),
          ],
          const SizedBox(height: 6),
          LinearProgressIndicator(value: passRate),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: PopupMenuButton<String>(
              tooltip: '更多',
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (v) {
                if (v == 'card') _viewAnswerCard(context, r);
                if (v == 'export') exportExamResultRecordUI(context, r);
                if (v == 'del') _deleteResult(context, r);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'card', child: Text('答题卡')),
                PopupMenuItem(value: 'export', child: Text('导出')),
                PopupMenuItem(value: 'del', child: Text('删除')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _passBadge(BuildContext context, ExamResult r) {
    if (r.totalScore <= 0) return const SizedBox.shrink();
    final pass = r.passed;
    final ungraded = !r.graded && r.subjectiveTotal > 0;
    final color = ungraded
        ? Colors.orange
        : (pass ? Colors.green : Colors.red);
    final label = ungraded
        ? '待评'
        : (pass ? '通过' : '未通过');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _typeBar(BuildContext context, QuestionType t, _TypeStat st) {
    final cs = Theme.of(context).colorScheme;
    final rate = st.total == 0 ? 0.0 : st.correct / st.total;
    return Row(
      children: [
        SizedBox(
            width: 64, child: Text(t.label, style: const TextStyle(fontSize: 12))),
        const SizedBox(width: 8),
        Expanded(
          child: LinearProgressIndicator(
            value: rate,
            backgroundColor: cs.surfaceContainerHighest,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text('${st.correct}/${st.total} ${(rate * 100).round()}%',
              style: const TextStyle(fontSize: 11), textAlign: TextAlign.right),
        ),
      ],
    );
  }

  Future<void> _deleteResult(
      BuildContext context, ExamResult r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除成绩单'),
        content: const Text('确认删除这张成绩单？此操作不可撤销。'),
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
    if (ok == true && context.mounted) {
      await context.read<PracticeExamProvider>().deleteExamResult(r.id);
    }
  }

  Widget _scoreBreakdown(BuildContext context, ExamResult r) {
    final cs = Theme.of(context).colorScheme;
    final objectiveTotal = r.totalScore - r.subjectiveTotal;
    if (r.subjectiveTotal == 0) {
      return Text('客观题 ${r.objectiveScore} / $objectiveTotal',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant));
    }
    return Row(
      children: [
        Text('客观 ${r.objectiveScore}/$objectiveTotal',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(width: 12),
        Text(
            r.graded
                ? '主观 ${r.subjectiveScore}/${r.subjectiveTotal}'
                : '主观 待评/${r.subjectiveTotal}',
            style: TextStyle(
                fontSize: 12,
                color: r.graded ? cs.onSurfaceVariant : Colors.orange,
                fontWeight:
                    r.graded ? FontWeight.normal : FontWeight.w600)),
        const Spacer(),
        if (!r.graded)
          TextButton.icon(
            icon: const Icon(Icons.rate_review, size: 16),
            label: const Text('去评卷'),
            onPressed: () => _gradeExam(context, r),
          ),
      ],
    );
  }

  Future<void> _gradeExam(BuildContext context, ExamResult r) async {
    final pe = context.read<PracticeExamProvider>();
    final all = await AppDatabase.instance.allQuestions();
    final map = {for (final q in all) q.id: q};
    final essays = r.questionIds
        .map((id) => map[id])
        .whereType<Question>()
        .where((q) => q.type == QuestionType.essay)
        .toList();
    if (essays.isEmpty) return;
    final maxPer = r.subjectiveTotal ~/ essays.length;
    if (maxPer <= 0) return;
    final scores = <String, int>{
      for (final q in essays) q.id: (_essayScore(r, q.id) ?? 0),
    };
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (sctx, set) => AlertDialog(
          title: const Text('主观题评卷'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final q in essays) ...[
                    Text(q.stem.isEmpty ? '（无题干）' : q.stem,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    Text('作答：${_essayAnswer(r, q.id)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                    Row(children: [
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: maxPer.toDouble(),
                          divisions: maxPer,
                          value: scores[q.id]!.toDouble(),
                          label: '${scores[q.id]}',
                          onChanged: (v) =>
                              set(() => scores[q.id] = v.round()),
                        ),
                      ),
                      SizedBox(
                          width: 50,
                          child: Text('${scores[q.id]}/$maxPer',
                              style: const TextStyle(fontSize: 12))),
                    ]),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await pe.gradeExam(r, scores, passRate: _passRateOf(pe, r));
              },
              child: const Text('保存评分'),
            ),
          ],
        ),
      ),
    );
  }

  int? _essayScore(ExamResult r, String qid) {
    for (final a in r.answers) {
      if (a.questionId == qid) return a.score;
    }
    return null;
  }

  String _essayAnswer(ExamResult r, String qid) {
    for (final a in r.answers) {
      if (a.questionId == qid) return a.userAnswer;
    }
    return '';
  }

  /// 取成绩单对应规则的及格比例（规则已删则默认 0.6）。
  double _passRateOf(PracticeExamProvider pe, ExamResult r) {
    for (final rule in pe.rules) {
      if (rule.id == r.ruleId) return rule.passRate;
    }
    return 0.6;
  }

  /// 答题卡：逐题查看题干/你的作答/正确答案/解析/得分；主观题在此评分（已评锁定）。
  Future<void> _viewAnswerCard(BuildContext context, ExamResult r) async {
    final pe = context.read<PracticeExamProvider>();
    final all = await AppDatabase.instance.allQuestions();
    final map = {for (final q in all) q.id: q};
    final questions =
        r.questionIds.map((id) => map[id]).whereType<Question>().toList();
    final records = {for (final a in r.answers) a.questionId: a};
    final essays = questions.where((q) => q.type == QuestionType.essay).toList();
    if (!context.mounted) return;
    await showAnswerCardDialog(
      context: context,
      title: '答题卡 · ${r.ruleName}',
      questions: questions,
      records: records,
      essayScoring: essays.isEmpty
          ? null
          : EssayScoring(
              subjectiveTotal: r.subjectiveTotal,
              lockedIds: {
                for (final q in essays)
                  if (_essayScore(r, q.id) != null) q.id,
              },
              scores: {
                for (final q in essays) q.id: (_essayScore(r, q.id) ?? 0),
              },
              onSave: (scores) =>
                  pe.gradeExam(r, scores, passRate: _passRateOf(pe, r)),
            ),
    );
  }

  Widget _warnChip(String text) => Chip(
        label: Text(text, style: const TextStyle(fontSize: 11)),
        backgroundColor: Colors.orange.withValues(alpha: 0.15),
        side: BorderSide.none,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      );

  Future<void> _exportExam(
      BuildContext context, PracticeExamProvider pe) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final export = ExportService();
    final all = await AppDatabase.instance.allQuestions();
    final map = {for (final q in all) q.id: q};
    final qids = <String>{};
    for (final r in pe.rules) {
      if (r.questionIds != null) qids.addAll(r.questionIds!);
    }
    final questions = qids.map((id) => map[id]).whereType<Question>().toList();
    if (!context.mounted) return;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出考试',
      fileName:
          'starhope_exam_${DateTime.now().millisecondsSinceEpoch}.starhope',
      type: FileType.custom,
      allowedExtensions: const ['starhope'],
    );
    if (path == null) return;
    final meta = export.buildMeta(user, ShareContentType.exam);
    try {
      await export.exportExam(
          path: path, rules: pe.rules, questions: questions, meta: meta);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出 ${pe.rules.length} 条考试规则')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _importExam(
      BuildContext context, PracticeExamProvider pe) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['starhope'],
    );
    if (result == null || result.files.single.path == null) return;
    final export = ExportService();
    final (file, error) =
        await export.importAndVerify(result.files.single.path!);
    if (file == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error ?? '校验失败')));
      return;
    }
    try {
      final count = await export.importExam(file);
      await pe.loadRulesAndResults();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已导入 $count 条考试规则')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  Future<void> _editRule(BuildContext context, ExamRule? existing) async {
    final qb = context.read<QuestionBankProvider>();
    final all = await AppDatabase.instance.allQuestions();
    if (!context.mounted) return;
    final name = TextEditingController(text: existing?.name ?? '');
    final count = TextEditingController(text: '${existing?.count ?? 20}');
    final duration =
        TextEditingController(text: '${existing?.durationMinutes ?? 30}');
    final score =
        TextEditingController(text: '${existing?.scorePerQuestion ?? 5}');
    final keyword =
        TextEditingController(text: existing?.filter.keyword ?? '');
    bool allowBack = existing?.allowReviewBack ?? true;
    double passRate = existing?.passRate ?? 0.6;
    List<String> selectedFolders = existing?.filter.folderIds.toList() ?? [];
    List<QuestionType> selectedTypes = existing?.filter.types.toList() ?? [];
    List<String> selectedTags = existing?.filter.tags.toList() ?? [];
    List<String>? selectedQuestions = existing?.questionIds?.toList();
    final quotaCtrls = {
      for (final t in QuestionType.values)
        t: TextEditingController(text: '${existing?.typeQuotas?[t] ?? ''}'),
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(existing == null ? '新建考试规则' : '编辑规则'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: '规则名称')),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: count,
                            decoration: const InputDecoration(
                                labelText: '题目数量', helperText: '配额为空时用'),
                            keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: duration,
                            decoration: const InputDecoration(
                                labelText: '时长(分)'),
                            keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: score,
                            decoration: const InputDecoration(
                                labelText: '每题分值'),
                            keyboardType: TextInputType.number)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Text('及格线'),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: 100,
                        divisions: 100,
                        value: passRate * 100,
                        label: '${(passRate * 100).round()}%',
                        onChanged: (v) => set(() => passRate = v / 100),
                      ),
                    ),
                    SizedBox(
                        width: 48,
                        child: Text('${(passRate * 100).round()}%',
                            style: const TextStyle(fontSize: 12))),
                  ]),
                  const Divider(height: 24),
                  Text('抽题范围（题型/标签/关键字/题库夹，均可不选 = 全部）',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in QuestionType.values)
                        FilterChip(
                          label: Text(t.label),
                          selected: selectedTypes.contains(t),
                          onSelected: (sel) => set(() {
                            selectedTypes = sel
                                ? [...selectedTypes, t]
                                : selectedTypes.where((x) => x != t).toList();
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: keyword,
                      decoration: const InputDecoration(
                          isDense: true,
                          hintText: '关键字（题干/解析）',
                          prefixIcon: Icon(Icons.search, size: 18))),
                  if (qb.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in qb.tags.take(15))
                          FilterChip(
                            label: Text('#$tag'),
                            selected: selectedTags.contains(tag),
                            onSelected: (sel) => set(() {
                              selectedTags = sel
                                  ? [...selectedTags, tag]
                                  : selectedTags.where((x) => x != tag).toList();
                            }),
                          ),
                      ],
                    ),
                  ],
                  if (qb.folders.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final f in qb.folders)
                          FilterChip(
                            label: Text(_folderPath(qb, f),
                                overflow: TextOverflow.ellipsis),
                            selected: selectedFolders.contains(f.id),
                            onSelected: (sel) => set(() {
                              if (sel) {
                                selectedFolders = [...selectedFolders, f.id];
                              } else {
                                selectedFolders = selectedFolders
                                    .where((x) => x != f.id)
                                    .toList();
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                  const Divider(height: 24),
                  Text('按题型配额抽题（任一填数即启用，覆盖"题目数量"）',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      for (final t in QuestionType.values)
                        SizedBox(
                          width: 92,
                          child: TextField(
                            controller: quotaCtrls[t],
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: t.label,
                              hintText: '0',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 24),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.handshake_outlined),
                    title: Text(selectedQuestions == null
                        ? '自定义选题（优先于以上抽题）'
                        : '自定义选题：${selectedQuestions!.length} 题（点击修改）'),
                    trailing: (selectedQuestions != null)
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: '清除自定义',
                            onPressed: () =>
                                set(() => selectedQuestions = null),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () async {
                      final picked = await pickQuestionsDialog(
                          ctx, all, selectedQuestions ?? const []);
                      if (picked != null) {
                        set(() => selectedQuestions =
                            picked.isEmpty ? null : picked);
                      }
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('允许回看'),
                    value: allowBack,
                    onChanged: (v) => set(() => allowBack = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      ),
    );
    // 释放配额控制器
    for (final c in quotaCtrls.values) {
      c.dispose();
    }
    keyword.dispose();
    if (saved != true) return;
    if (!context.mounted) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final filter = QuestionFilter(
      tags: selectedTags,
      types: selectedTypes,
      folderIds: selectedFolders,
      keyword: keyword.text,
    );
    final quotas = <QuestionType, int>{};
    for (final e in quotaCtrls.entries) {
      final n = int.tryParse(e.value.text);
      if (n != null && n > 0) quotas[e.key] = n;
    }
    final rule = ExamRule(
      id: existing?.id ?? CryptoServiceId.gen(),
      name: name.text.isEmpty ? '考试' : name.text,
      filter: filter,
      count: int.tryParse(count.text) ?? 20,
      durationMinutes: int.tryParse(duration.text) ?? 30,
      scorePerQuestion: int.tryParse(score.text) ?? 5,
      allowReviewBack: allowBack,
      questionIds: selectedQuestions,
      typeQuotas: quotas.isEmpty ? null : quotas,
      passRate: passRate,
      createdAt: existing?.createdAt ?? now,
    );
    await context.read<PracticeExamProvider>().saveRule(rule);
  }

  String _folderPath(QuestionBankProvider qb, QuestionFolder f) {
    final chain = qb.folderChain(f.parentId);
    final names = chain.map((x) => x.name).join(' / ');
    return names.isEmpty ? f.name : '$names / ${f.name}';
  }

  Future<void> _startExam(
      BuildContext context, PracticeExamProvider pe, ExamRule r) async {
    final qb = context.read<QuestionBankProvider>();
    List<Question> questions;
    if (r.isPinned) {
      // 自定义选题：按固定 id 从库加载（保持规则定义的顺序）
      final all = await AppDatabase.instance.allQuestions();
      final map = {for (final q in all) q.id: q};
      questions =
          r.questionIds!.map((id) => map[id]).whereType<Question>().toList();
    } else if (r.hasTypeQuotas) {
      // 按题型配额抽题
      questions = await qb.pickByQuotas(
          filter: r.filter, quotas: r.typeQuotas!, random: true);
    } else {
      questions = await qb.pickQuestions(
          filter: r.filter, random: true, count: r.count);
    }
    if (!context.mounted) return;
    final want = r.effectiveCount;
    if (questions.length < want) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '题库符合条件题目不足（仅 ${questions.length}/$want 题），将以此数量开考')));
    }
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有符合条件的题目')));
      return;
    }
    await pe.startExam(r, questions);
  }

  // ============ 考试进行中 ============
  Widget _examRunning(BuildContext context, PracticeExamProvider pe) {
    final cs = Theme.of(context).colorScheme;
    final q = pe.examQuestions[pe.examIndex];
    final remaining = pe.examRemainingSec;
    final min = remaining ~/ 60;
    final sec = remaining % 60;
    final lowTime = remaining < 60;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 顶栏：计时 + 规则名 + 交卷
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.timer, color: lowTime ? Colors.red : cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(pe.activeRule!.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text(
                      '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: lowTime ? Colors.red : cs.primary)),
                  const SizedBox(width: 12),
                  if (pe.focusLost > 0 || pe.timeAnomaly)
                    const Icon(Icons.warning, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _confirmSubmit(context, pe),
                    child: const Text('交卷'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左 1/5：答题卡
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width * 0.2,
                    child: GlassCard(
                      padding: const EdgeInsets.all(8),
                      child: _answerSheet(context, pe),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 右 4/5：题目栏
                  Expanded(
                    child: GlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              QTypeChip(type: q.type),
                              const SizedBox(width: 8),
                              Text(
                                  '第 ${pe.examIndex + 1} / ${pe.examQuestions.length} 题',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant)),
                              const Spacer(),
                              IconButton(
                                tooltip: pe.examReview.contains(q.id)
                                    ? '取消标记'
                                    : '标记待复习',
                                icon: Icon(
                                    pe.examReview.contains(q.id)
                                        ? Icons.flag
                                        : Icons.flag_outlined,
                                    color: pe.examReview.contains(q.id)
                                        ? Colors.orange
                                        : null,
                                    size: 20),
                                onPressed: () => pe.toggleExamReview(q.id),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView(
                              children: [
                                MarkdownPreview(q.stem, selectable: true),
                                const SizedBox(height: 16),
                                AnswerInput(
                                  question: q,
                                  value: pe.examAnswers[q.id] ?? '',
                                  onChanged: (v) =>
                                      pe.setExamAnswer(q.id, v),
                                ),
                              ],
                            ),
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: pe.examIndex > 0 &&
                                        pe.activeRule!.allowReviewBack
                                    ? () => pe.gotoExamIndex(pe.examIndex - 1)
                                    : null,
                                child: const Text('上一题'),
                              ),
                              TextButton(
                                onPressed: pe.examIndex <
                                        pe.examQuestions.length - 1
                                    ? () => pe.gotoExamIndex(pe.examIndex + 1)
                                    : () => _confirmSubmit(context, pe),
                                child: Text(
                                    pe.examIndex < pe.examQuestions.length - 1
                                        ? '下一题'
                                        : '交卷'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 答题卡：题号网格，标记 已答/当前/待复习
  Widget _answerSheet(BuildContext context, PracticeExamProvider pe) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('答题卡',
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < pe.examQuestions.length; i++)
                InkWell(
                  onTap: () => pe.gotoExamIndex(i),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == pe.examIndex
                          ? cs.primary
                          : (pe.examAnswers
                                  .containsKey(pe.examQuestions[i].id)
                              ? cs.primaryContainer
                              : cs.surfaceContainerHighest),
                      borderRadius: BorderRadius.circular(8),
                      border: pe.examReview.contains(pe.examQuestions[i].id)
                          ? Border.all(color: Colors.orange, width: 2)
                          : null,
                    ),
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 13,
                            color: i == pe.examIndex ? cs.onPrimary : null,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Container(
                width: 10, height: 10, color: cs.primaryContainer),
            const SizedBox(width: 4),
            Text('已答',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(border: Border.all(color: Colors.orange, width: 2))),
            const SizedBox(width: 4),
            Text('待复习',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          ]),
        ],
      ),
    );
  }

  Future<void> _confirmSubmit(
      BuildContext context, PracticeExamProvider pe) async {
    final unanswered =
        pe.examQuestions.where((q) => !pe.examAnswers.containsKey(q.id)).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认交卷'),
        content: Text(unanswered > 0
            ? '还有 $unanswered 题未作答，确认交卷？'
            : '确认交卷？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('交卷')),
        ],
      ),
    );
    if (ok == true) {
      final result = await pe.submitExam();
      if (context.mounted) {
        final all = await AppDatabase.instance.allQuestions();
        if (!context.mounted) return;
        final map = {for (final q in all) q.id: q};
        final byType = <QuestionType, _TypeStat>{};
        final wrongQs = <Question>[];
        for (final a in result.answers) {
          final q = map[a.questionId];
          if (q == null) continue;
          final st = byType.putIfAbsent(q.type, () => _TypeStat());
          st.total++;
          if (a.correct) {
            st.correct++;
          } else {
            wrongQs.add(q);
          }
        }
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('考试完成'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('得分：${result.score} / ${result.totalScore}'
                        '${result.passed ? "  ✓ 通过" : (result.totalScore > 0 ? "  ✗ 未通过" : "")}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('正确 ${result.correctCount} · 错误 ${result.wrongCount}'),
                    if (result.focusLostCount > 0)
                      Text('失焦 ${result.focusLostCount} 次',
                          style: const TextStyle(color: Colors.orange)),
                    if (result.timeAnomaly)
                      const Text('检测到系统时间异常',
                          style: TextStyle(color: Colors.orange)),
                    if (result.autoSubmitted)
                      const Text('因超时自动交卷',
                          style: TextStyle(color: Colors.orange)),
                    if (byType.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text('各题型正确率',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      for (final entry in byType.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _typeBar(ctx, entry.key, entry.value),
                        ),
                    ],
                    const SizedBox(height: 8),
                    const Text('错题已自动加入错题本。',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
            actions: [
              if (wrongQs.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.replay),
                  label: const Text('重练错题'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    pe.startPractice(wrongQs, mode: 'instant');
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PracticePage()));
                  },
                ),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('完成')),
            ],
          ),
        );
      }
    }
  }
}

class _TypeStat {
  int total = 0;
  int correct = 0;
}
