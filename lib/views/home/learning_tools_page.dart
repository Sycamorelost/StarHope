import 'package:flutter/material.dart';

import '../common/glass.dart';
import 'exam_page.dart';
import 'practice_page.dart';
import 'question_bank_page.dart';
import 'reader_page.dart';
import 'wrong_book_page.dart';

/// 学习工具页：把 题库/练习/考试/错题本/阅读 聚合成玻璃块，点击 push 进入对应功能页
/// （全局 slide 过渡，返回回本页）。
class LearningToolsPage extends StatelessWidget {
  const LearningToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('学习工具',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('选择一个模块开始',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.15,
              children: [
                _block(context, Icons.library_books_outlined, '题库',
                    '题目 / 文件夹 / 导入导出', const QuestionBankPage()),
                _block(context, Icons.fitness_center_outlined, '练习',
                    '刷题与统计', const PracticePage()),
                _block(context, Icons.school_outlined, '考试',
                    '组卷与阅卷', const ExamPage()),
                _block(context, Icons.error_outline, '错题本',
                    '错题归类与重练', const WrongBookPage()),
                _block(context, Icons.menu_book_outlined, '阅读',
                    '文档阅读与批注', const ReaderPage()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, IconData icon, String title,
      String subtitle, Widget page) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primaryContainer,
            ),
            child: Icon(icon, size: 28, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 10),
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
