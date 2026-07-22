import 'package:flutter/material.dart';

import '../../../core/models/question.dart';

/// 题目多选对话框：从给定题目集合中勾选任意题目，返回选中的 id 列表。
/// 返回 null 表示用户取消；空列表表示"清空自定义"。
/// 取代 exam 页的 _pickExamQuestions，练习/考试共用。
Future<List<String>?> pickQuestionsDialog(
  BuildContext context,
  List<Question> all,
  List<String> initial,
) async {
  final selected = <String>{...initial};
  if (!context.mounted) return null;
  return showDialog<List<String>?>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (sctx, set) => AlertDialog(
        title: Text('自定义选题（共 ${all.length} 题可选）'),
        content: SizedBox(
          width: 420,
          child: all.isEmpty
              ? const Text('题库为空，请先添加题目。')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: all.length,
                  itemBuilder: (_, i) {
                    final q = all[i];
                    return CheckboxListTile(
                      dense: true,
                      value: selected.contains(q.id),
                      title: Text(q.stem.isEmpty ? '（无题干）' : q.stem,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${q.type.label} · ${q.tags.join(", ")}',
                          style: const TextStyle(fontSize: 11)),
                      onChanged: (v) => set(() {
                        if (v == true) {
                          selected.add(q.id);
                        } else {
                          selected.remove(q.id);
                        }
                      }),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, selected.toList()),
            child: Text('确定（${selected.length}）'),
          ),
        ],
      ),
    ),
  );
}
