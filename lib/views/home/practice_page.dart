import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/models/models.dart';
import '../../core/models/question.dart';
import '../../providers/practice_exam_provider.dart';
import '../../providers/question_provider.dart';
import '../../services/database/database.dart';
import '../common/glass.dart';
import 'widgets/answer_card_dialog.dart';
import 'widgets/import_export_dialogs.dart';
import 'widgets/answer_widgets.dart';
import 'widgets/question_picker.dart';
import 'widgets/question_tile.dart';

class PracticePage extends StatefulWidget {
  const PracticePage({super.key});
  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  // 练习设置
  int _count = 10;
  bool _random = true;
  bool _wrongFirst = false;
  String _mode = 'instant'; // instant 边练边判 / batch 集中判题
  List<String>? _customIds; // 自定义选题（null = 按参数抽题）
  // 即时模式单题计时
  String? _shownQid;
  int _qStartMs = 0;

  @override
  Widget build(BuildContext context) {
    final pe = context.watch<PracticeExamProvider>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: pe.practice == null ? _setupView(context) : _runningView(context),
      ),
    );
  }

  // ===================== 设置页 =====================
  Widget _setupView(BuildContext context) {
    final qb = context.watch<QuestionBankProvider>();
    final pe = context.read<PracticeExamProvider>();
    return StatefulBuilder(
      builder: (_, set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('练习',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前筛选条件',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _filterSummary(context, qb),
                const SizedBox(height: 8),
                Text('题库总量：${qb.questions.length} 道',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                // 判题模式
                Text('判题模式', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'instant',
                        label: Text('边练边判'),
                        icon: Icon(Icons.flash_on, size: 18)),
                    ButtonSegment(
                        value: 'batch',
                        label: Text('集中判题'),
                        icon: Icon(Icons.receipt_long_outlined, size: 18)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => set(() => _mode = s.first),
                ),
                const SizedBox(height: 12),
                // 自定义选题
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.handshake_outlined),
                  title: Text(_customIds == null
                      ? '自定义选题（不选则按下方参数抽题）'
                      : '已自定义选题：${_customIds!.length} 题（点击修改）'),
                  trailing: _customIds == null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: '清除自定义',
                          onPressed: () => set(() => _customIds = null),
                        ),
                  onTap: () async {
                    final all = await AppDatabase.instance.allQuestions();
                    if (!context.mounted) return;
                    final picked = await pickQuestionsDialog(
                        context, all, _customIds ?? const []);
                    if (picked != null) {
                      set(() =>
                          _customIds = picked.isEmpty ? null : picked);
                    }
                  },
                ),
                if (_customIds == null) ...[
                  Row(
                    children: [
                      const Text('抽取数量'),
                      Expanded(
                        child: Slider(
                          min: 1,
                          max: qb.questions.length.toDouble().clamp(1, 100),
                          divisions: qb.questions.length > 1
                              ? qb.questions.length - 1
                              : 1,
                          value: _count
                              .toDouble()
                              .clamp(1, qb.questions.length.toDouble().clamp(1, 100)),
                          label: '$_count',
                          onChanged: qb.questions.isEmpty
                              ? null
                              : (v) => set(() => _count = v.round()),
                        ),
                      ),
                      SizedBox(width: 40, child: Text('$_count')),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('随机顺序'),
                    value: _random,
                    onChanged: (v) => set(() => _random = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('错题优先（按错次）'),
                    value: _wrongFirst,
                    onChanged: (v) => set(() => _wrongFirst = v),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: qb.questions.isEmpty
                        ? null
                        : () => _start(context, qb, pe),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_customIds != null
                        ? '开始练习（${_customIds!.length} 题）'
                        : '开始练习'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (pe.practiceHistory.isNotEmpty) ...[
            Text('历史记录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: pe.practiceHistory.length,
                itemBuilder: (_, i) {
                  final s = pe.practiceHistory[i];
                  return _historyCard(context, pe, s);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _historyCard(
      BuildContext context, PracticeExamProvider pe, PracticeSession s) {
    final correct = s.answers.where((a) => a.correct).length;
    final ongoing = s.status != 'finished';
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(ongoing ? Icons.play_circle_outline : Icons.history,
              color: ongoing ? cs.primary : null),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: s.answers.isNotEmpty
                  ? () => _viewCard(context, s)
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s.mode == 'batch' ? '集中判题' : '边练边判'} · '
                    '${s.questionIds.length} 题 · '
                    '${ongoing ? "进行中（${s.currentIndex}/${s.questionIds.length}）" : "正确 $correct/${s.answers.length}"}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  Text(_formatTime(s.startedAt),
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ),
          if (ongoing)
            IconButton(
              tooltip: '继续',
              icon: const Icon(Icons.play_arrow, size: 20),
              onPressed: () => pe.resumePractice(s.id),
            ),
          IconButton(
            tooltip: '导出',
            icon: const Icon(Icons.ios_share, size: 20),
            onPressed: () => exportPracticeRecordUI(context, s),
          ),
          IconButton(
            tooltip: '答题卡',
            icon: const Icon(Icons.menu_book_outlined, size: 20),
            onPressed: s.answers.isEmpty ? null : () => _viewCard(context, s),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () async {
              final ok = await _confirmDelete(context);
              if (ok == true) await pe.deletePractice(s.id);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _viewCard(BuildContext context, PracticeSession s) async {
    final all = await AppDatabase.instance.allQuestions();
    final map = {for (final q in all) q.id: q};
    final questions =
        s.questionIds.map((id) => map[id]).whereType<Question>().toList();
    final records = {for (final a in s.answers) a.questionId: a};
    if (!context.mounted) return;
    await showAnswerCardDialog(
      context: context,
      title: '练习答题卡',
      questions: questions,
      records: records,
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确认删除这次练习记录？此操作不可撤销。'),
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
  }

  Future<void> _start(BuildContext context, QuestionBankProvider qb,
      PracticeExamProvider pe) async {
    List<Question> questions;
    QuestionFilter filter;
    if (_customIds != null) {
      final all = await AppDatabase.instance.allQuestions();
      final map = {for (final q in all) q.id: q};
      questions =
          _customIds!.map((id) => map[id]).whereType<Question>().toList();
      filter = qb.toFilter();
    } else {
      filter = qb.toFilter(wrongFirst: _wrongFirst, limit: _count);
      questions = await qb.pickQuestions(
          filter: filter, random: _random, count: _count);
    }
    if (!context.mounted) return;
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有符合条件的题目')));
      return;
    }
    await pe.startPractice(questions, filter: filter, mode: _mode);
  }

  // ===================== 进行中 =====================
  Widget _runningView(BuildContext context) {
    final pe = context.watch<PracticeExamProvider>();
    final session = pe.practice!;
    final idx = session.currentIndex;
    if (idx >= session.questionIds.length) {
      return _summaryView(context, pe, session);
    }
    if (session.mode == 'batch') return _batchRunningView(context, pe, session);
    // instant
    return FutureBuilder<Question?>(
      future: AppDatabase.instance.getQuestion(session.questionIds[idx]),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final q = snap.data!;
        if (_shownQid != q.id) {
          _shownQid = q.id;
          _qStartMs = DateTime.now().millisecondsSinceEpoch;
        }
        final answered = session.answers.any((a) => a.questionId == q.id);
        final answer = pe.pendingAnswers[q.id] ?? '';
        return Column(
          children: [
            _progressBar(context, pe, session, idx, answered),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        QTypeChip(type: q.type),
                        const SizedBox(height: 8),
                        MarkdownPreview(q.stem, selectable: true),
                        const SizedBox(height: 16),
                        AnswerInput(
                          question: q,
                          value: answer,
                          enabled: !answered,
                          onChanged: (v) => pe.setPracticeAnswer(q.id, v),
                        ),
                        if (answered) ...[
                          const SizedBox(height: 16),
                          _resultView(context, q, session),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!answered)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: answer.isEmpty
                        ? null
                        : () {
                            final used =
                                (DateTime.now().millisecondsSinceEpoch - _qStartMs) ~/
                                    1000;
                            pe.submitPracticeAnswer(q, answer, used);
                          },
                    icon: const Icon(Icons.check),
                    label: const Text('提交'),
                  ),
                ),
              ),
            if (answered)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await pe.advancePractice();
                      if (pe.practice!.currentIndex >=
                          pe.practice!.questionIds.length) {
                        await pe.finishPractice();
                      }
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('下一题'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _progressBar(BuildContext context, PracticeExamProvider pe,
      PracticeSession session, int idx, bool answered) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text('${idx + 1} / ${session.questionIds.length}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 16),
          Expanded(
            child: LinearProgressIndicator(
              value: (idx + (answered ? 1 : 0)) / session.questionIds.length,
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _confirmExit(context, pe),
          ),
        ],
      ),
    );
  }

  /// 集中判题模式：仿考试布局（答题卡导航 + 上下题 + 不显对错），完成收卷。
  Widget _batchRunningView(
      BuildContext context, PracticeExamProvider pe, PracticeSession session) {
    final cs = Theme.of(context).colorScheme;
    final idx = session.currentIndex;
    return FutureBuilder<Question?>(
      future: AppDatabase.instance.getQuestion(session.questionIds[idx]),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final q = snap.data!;
        final answer = pe.pendingAnswers[q.id] ?? '';
        return Column(
          children: [
            _progressBar(context, pe, session, idx,
                pe.pendingAnswers.containsKey(q.id)),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 150,
                    child: GlassCard(
                      padding: const EdgeInsets.all(8),
                      child: _batchAnswerSheet(context, pe, session),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          QTypeChip(type: q.type),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView(
                              children: [
                                MarkdownPreview(q.stem, selectable: true),
                                const SizedBox(height: 16),
                                AnswerInput(
                                  question: q,
                                  value: answer,
                                  onChanged: (v) =>
                                      pe.setPracticeAnswer(q.id, v),
                                ),
                              ],
                            ),
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: idx > 0
                                    ? () => pe.advanceTo(idx - 1)
                                    : null,
                                child: const Text('上一题'),
                              ),
                              if (idx < session.questionIds.length - 1)
                                TextButton(
                                  onPressed: () => pe.advanceTo(idx + 1),
                                  child: const Text('下一题'),
                                )
                              else
                                FilledButton.icon(
                                  onPressed: () => _confirmFinishBatch(context, pe),
                                  icon: const Icon(Icons.check),
                                  label: const Text('完成练习'),
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
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: cs.primary),
                  onPressed: () => _confirmFinishBatch(context, pe),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('完成练习并判题'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _batchAnswerSheet(
      BuildContext context, PracticeExamProvider pe, PracticeSession session) {
    final cs = Theme.of(context).colorScheme;
    final answeredIds = pe.pendingAnswers.keys.toSet();
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
              for (var i = 0; i < session.questionIds.length; i++)
                InkWell(
                  onTap: () => pe.advanceTo(i),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == session.currentIndex
                          ? cs.primary
                          : (answeredIds.contains(session.questionIds[i])
                              ? cs.primaryContainer
                              : cs.surfaceContainerHighest),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 12,
                            color: i == session.currentIndex
                                ? cs.onPrimary
                                : null)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmFinishBatch(
      BuildContext context, PracticeExamProvider pe) async {
    final session = pe.practice!;
    final unanswered = session.questionIds
        .where((id) => !pe.pendingAnswers.containsKey(id))
        .length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('完成练习'),
        content: Text(unanswered > 0
            ? '还有 $unanswered 题未作答，确认完成并判题？'
            : '确认完成并判题？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('完成')),
        ],
      ),
    );
    if (ok != true) return;
    await pe.finishBatchPractice();
    if (!context.mounted) return;
    await _viewCard(context, pe.practice!);
  }

  Widget _resultView(BuildContext context, Question q, PracticeSession session) {
    AnswerRecord? record;
    for (final a in session.answers) {
      if (a.questionId == q.id) {
        record = a;
        break;
      }
    }
    if (record == null) return const SizedBox.shrink();
    final correct = record.correct;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (correct ? Colors.green : Colors.red).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: (correct ? Colors.green : Colors.red).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(correct ? Icons.check_circle : Icons.cancel,
                  color: correct ? Colors.green : Colors.red),
              const SizedBox(width: 8),
              Text(correct ? '回答正确' : '回答错误',
                  style: TextStyle(
                      color: correct ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text('你的答案：${displayAnswer(q, record.userAnswer)}',
              style: const TextStyle(fontSize: 13)),
          Text('正确答案：${displayAnswer(q, q.answer)}',
              style: const TextStyle(fontSize: 13)),
          if (q.explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('解析', style: TextStyle(fontWeight: FontWeight.bold)),
            MarkdownPreview(q.explanation, selectable: true),
          ],
          if (q.isFromShare) ...[
            const SizedBox(height: 8),
            SourceBadge(nickname: q.sourceNickname, authorId: q.sourceAuthorId),
          ],
        ],
      ),
    );
  }

  // ===================== 完成统计页 =====================
  Widget _summaryView(
      BuildContext context, PracticeExamProvider pe, PracticeSession s) {
    final correct = s.answers.where((a) => a.correct).length;
    final total = s.answers.length;
    final totalSec = (s.finishedAt ?? s.startedAt) - s.startedAt;
    return FutureBuilder<List<Question>>(
      future: AppDatabase.instance.allQuestions(),
      builder: (_, snap) {
        final all = snap.data ?? const [];
        final map = {for (final q in all) q.id: q};
        // 各题型正确率
        final byType = <QuestionType, _TypeStat>{};
        for (final a in s.answers) {
          final q = map[a.questionId];
          if (q == null) continue;
          final st = byType.putIfAbsent(q.type, () => _TypeStat());
          st.total++;
          if (a.correct) st.correct++;
        }
        final wrongQs = s.answers
            .where((a) => !a.correct)
            .map((a) => map[a.questionId])
            .whereType<Question>()
            .toList();
        return Center(
          child: GlassCard(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.emoji_events,
                          size: 48, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('练习完成',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            Text('$correct / $total 正确 · 用时 ${_fmtSec(totalSec)}',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (byType.isNotEmpty) ...[
                    const Text('各题型正确率',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    for (final entry in byType.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _typeBar(context, entry.key, entry.value),
                      ),
                  ],
                  if (wrongQs.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('错题 ${wrongQs.length} 道',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          pe.clearPractice();
                          pe.startPractice(wrongQs,
                              filter: s.filter, mode: 'instant');
                        },
                        icon: const Icon(Icons.replay),
                        label: const Text('立即重练这些错题'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _viewCard(context, s),
                          icon: const Icon(Icons.menu_book_outlined),
                          label: const Text('答题卡'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => pe.clearPractice(),
                          child: const Text('返回'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _typeBar(BuildContext context, QuestionType t, _TypeStat st) {
    final cs = Theme.of(context).colorScheme;
    final rate = st.total == 0 ? 0.0 : st.correct / st.total;
    return Row(
      children: [
        SizedBox(width: 64, child: Text(t.label, style: const TextStyle(fontSize: 12))),
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
          width: 56,
          child: Text('${st.correct}/${st.total} ${(rate * 100).round()}%',
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.right),
        ),
      ],
    );
  }

  Widget _filterSummary(BuildContext context, QuestionBankProvider qb) {
    final parts = <String>[];
    if (qb.currentFolderId != null) {
      final chain = qb.folderChain(qb.currentFolderId);
      parts.add('夹:${chain.map((f) => f.name).join('/')}');
    }
    if (qb.typeFilter.isNotEmpty) {
      parts.add(qb.typeFilter.map((t) => t.label).join('/'));
    }
    if (qb.tagFilter.isNotEmpty) {
      parts.add(qb.tagFilter.map((t) => '#$t').join(' '));
    }
    if (qb.sourceFilter != null) parts.add('来源:${qb.sourceFilter}');
    if (qb.keyword.isNotEmpty) parts.add('“${qb.keyword}”');
    return Text(parts.isEmpty ? '无（全部题目）' : parts.join(' · '),
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
  }

  String _formatTime(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms).toString().substring(0, 16);

  String _fmtSec(int ms) {
    final s = ms ~/ 1000;
    if (s < 60) return '$s 秒';
    final m = s ~/ 60;
    return '$m 分 ${s % 60} 秒';
  }

  Future<void> _confirmExit(
      BuildContext context, PracticeExamProvider pe) async {
    final session = pe.practice!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出练习'),
        content: Text(session.mode == 'batch'
            ? '进度已自动保存（含未判作答），可从历史"继续"。确认退出？'
            : '进度已自动保存，可从历史"继续"。确认退出？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('退出')),
        ],
      ),
    );
    if (ok == true) {
      // 保留为 ongoing（进度已落库），可从历史"继续"；不标记 finished
      pe.clearPractice();
    }
  }
}

class _TypeStat {
  int total = 0;
  int correct = 0;
}
