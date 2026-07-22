import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/models/models.dart';
import '../../../core/models/question.dart';
import 'answer_widgets.dart';

/// 主观题评分上下文（仅考试侧需要；练习侧传 null 即只读）。
/// [scores] 为可变工作副本（对话框内随滑块更新），[onSave] 在"保存评分"时触发。
class EssayScoring {
  final int subjectiveTotal;
  final Set<String> lockedIds;
  final Map<String, int> scores;
  final Future<void> Function(Map<String, int> scores) onSave;
  const EssayScoring({
    required this.subjectiveTotal,
    required this.lockedIds,
    required this.scores,
    required this.onSave,
  });
}

/// 答题卡对话框（surveyking 式）：逐题展示题干/你的答案/正确答案/解析/得分。
/// 取代 exam 页的 _viewAnswerCard；练习历史、集中判题结束、考试成绩单共用。
Future<void> showAnswerCardDialog({
  required BuildContext context,
  required String title,
  required List<Question> questions,
  required Map<String, AnswerRecord> records,
  EssayScoring? essayScoring,
}) async {
  final essays = questions.where((q) => q.type == QuestionType.essay).toList();
  final maxPer = essays.isNotEmpty && essayScoring != null
      ? essayScoring.subjectiveTotal ~/ essays.length
      : 0;
  final hasUngradedEssay = essayScoring != null &&
      essays.any((q) => !essayScoring.lockedIds.contains(q.id));

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (sctx, set) => AlertDialog(
        title: Text('$title（${questions.length} 题）'),
        content: SizedBox(
          width: 560,
          child: questions.isEmpty
              ? const Text('无题目。')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: questions.length,
                  itemBuilder: (_, i) {
                    final q = questions[i];
                    final rec = records[q.id];
                    final isEssay = q.type == QuestionType.essay;
                    final isLocked =
                        essayScoring?.lockedIds.contains(q.id) ?? false;
                    final score = essayScoring?.scores[q.id] ?? 0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              QTypeChip(type: q.type),
                              const SizedBox(width: 6),
                              Text('第 ${i + 1} 题',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                              const Spacer(),
                              if (isEssay && essayScoring != null)
                                Text(
                                    isLocked
                                        ? '主观 $score/$maxPer'
                                        : '主观 待评',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: isLocked
                                            ? Colors.green
                                            : Colors.orange,
                                        fontWeight: FontWeight.w600))
                              else
                                Text(rec?.correct == true ? '✓ 正确' : '✗ 错误',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: rec?.correct == true
                                            ? Colors.green
                                            : Colors.red)),
                            ]),
                            const SizedBox(height: 4),
                            Text(q.stem.isEmpty ? '（无题干）' : q.stem,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                                '你的答案：${rec == null || rec.userAnswer.isEmpty ? "（未作答）" : rec.userAnswer}',
                                style: const TextStyle(fontSize: 12)),
                            if (!isEssay)
                              Text('正确答案：${displayAnswer(q, q.answer)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            if (q.explanation.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('解析：${q.explanation}',
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                            ],
                            if (isEssay &&
                                essayScoring != null &&
                                maxPer > 0) ...[
                              const SizedBox(height: 4),
                              if (isLocked)
                                const Text('已评分（不可更改）',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.green))
                              else
                                Row(children: [
                                  const Text('评分'),
                                  Expanded(
                                    child: Slider(
                                      min: 0,
                                      max: maxPer.toDouble(),
                                      divisions: maxPer,
                                      value: score.toDouble(),
                                      label: '$score',
                                      onChanged: (v) => set(() =>
                                          essayScoring.scores[q.id] = v.round()),
                                    ),
                                  ),
                                  SizedBox(
                                      width: 50,
                                      child: Text('$score/$maxPer',
                                          style:
                                              const TextStyle(fontSize: 12))),
                                ]),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          if (essayScoring != null && hasUngradedEssay)
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await essayScoring.onSave(essayScoring.scores);
              },
              child: const Text('保存评分'),
            ),
        ],
      ),
    ),
  );
}
