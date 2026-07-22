import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/ai_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/practice_exam_provider.dart';
import '../../providers/question_provider.dart';
import '../common/glass.dart';

/// 摘要主页：登录后默认首页，聚合用户信息与各模块数据概览。
class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key});
  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final qb = context.watch<QuestionBankProvider>();
    final pe = context.watch<PracticeExamProvider>();
    final ai = context.watch<AIProvider>();
    final user = auth.user;
    final cs = Theme.of(context).colorScheme;
    final avatarPath = user?.avatarPath;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('摘要',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // 用户卡片
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: cs.primaryContainer,
                  backgroundImage: (avatarPath != null &&
                          File(avatarPath).existsSync())
                      ? FileImage(File(avatarPath))
                      : null,
                  child: (avatarPath == null || !File(avatarPath).existsSync())
                      ? Text(
                          (user?.nickname ?? '?').characters.first.toUpperCase(),
                          style: TextStyle(
                              fontSize: 22, color: cs.onPrimaryContainer),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.nickname ?? '用户',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('@${user?.account ?? ''}',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (user?.github != null && user!.github!.isNotEmpty)
                            _socialChip(Icons.code, 'GitHub: ${user.github}', cs),
                          if (user?.qq != null && user!.qq!.isNotEmpty)
                            _socialChip(Icons.chat, 'QQ: ${user.qq}', cs),
                          if (user?.wechat != null && user!.wechat!.isNotEmpty)
                            _socialChip(Icons.wechat_outlined,
                                '微信: ${user.wechat}', cs),
                          if ((user?.github == null ||
                                  user!.github!.isEmpty) &&
                              (user?.qq == null || user!.qq!.isEmpty) &&
                              (user?.wechat == null || user!.wechat!.isEmpty))
                            Text('未设置社交账号',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 数据摘要网格
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 4.5,
            children: [
              _statCard('题库题目', qb.questions.length, Icons.library_books_outlined,
                  cs.primary, cs),
              _statCard('题库文件夹', qb.folders.length, Icons.folder_outlined,
                  cs.tertiary, cs),
              _statCard('错题本', pe.wrongCount, Icons.error_outline,
                  Colors.red.shade400, cs),
              _statCard('AI 智能体', ai.agents.length, Icons.smart_toy_outlined,
                  cs.secondary, cs),
              _statCard('考试规则', pe.rules.length, Icons.school_outlined,
                  cs.primary, cs),
              _statCard('考试记录', pe.results.length,
                  Icons.assignment_turned_in_outlined, cs.tertiary, cs),
            ],
          ),
        ],
      ),
    );
  }

  Widget _socialChip(IconData icon, String text, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(fontSize: 11, color: cs.onSecondaryContainer)),
        ],
      ),
    );
  }

  Widget _statCard(
      String title, int count, IconData icon, Color color, ColorScheme cs) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 8),
          Text('$count',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
