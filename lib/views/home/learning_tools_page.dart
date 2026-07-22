import 'package:flutter/material.dart';

import '../common/glass.dart';
import 'exam_page.dart';
import 'practice_page.dart';
import 'question_bank_page.dart';
import 'reader_page.dart';
import 'wrong_book_page.dart';

/// 学习工具页：5 个模块玻璃块全部显示在一页——首行 3 块（题库/练习/考试），
/// 次行 2 块（错题本/阅读，左右等长）。点击 push 进入对应功能页（全局 slide 过渡）。
class LearningToolsPage extends StatelessWidget {
  const LearningToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
              style:
                  TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          // 首行：题库 / 练习 / 考试（3 块等宽）
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                    child: _block(context, Icons.library_books_outlined, '题库',
                        '题目 / 文件夹 / 导入导出', const QuestionBankPage())),
                const SizedBox(width: 12),
                Expanded(
                    child: _block(context, Icons.fitness_center_outlined,
                        '练习', '刷题与统计', const PracticePage())),
                const SizedBox(width: 12),
                Expanded(
                    child: _block(context, Icons.school_outlined, '考试',
                        '组卷与阅卷', const ExamPage())),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 次行：错题本 / 阅读（2 块左右等长）
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                    child: _block(context, Icons.error_outline, '错题本',
                        '错题归类与重练', const WrongBookPage())),
                const SizedBox(width: 12),
                Expanded(
                    child: _block(context, Icons.menu_book_outlined, '阅读',
                        '文档阅读与批注', const ReaderPage())),
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
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primaryContainer,
            ),
            child: Icon(icon, size: 26, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 8),
          Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
