import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// 导入模板与统一规范对话框
///
/// 展示 StarHope 题库对各导入文件类型的字段规范与示例，并提供下载示例模板。
class ImportTemplateDialog extends StatefulWidget {
  const ImportTemplateDialog({super.key});
  @override
  State<ImportTemplateDialog> createState() => _ImportTemplateDialogState();
}

class _ImportTemplateDialogState extends State<ImportTemplateDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 780,
        height: 640,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined),
                  const SizedBox(width: 8),
                  const Text('导入模板与规范',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(),
            // 统一字段说明
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: _fieldSpec(context),
            ),
            TabBar(
              controller: _tab,
              isScrollable: true,
              tabs: const [
                Tab(text: 'CSV'),
                Tab(text: 'HTML'),
                Tab(text: 'Markdown'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _codeTab(_csvExample, 'csv', 'questions.csv'),
                  _codeTab(_htmlExample, 'html', 'questions.html'),
                  _codeTab(_mdExample, 'md', 'questions.md'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldSpec(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('统一字段规范（所有格式共用）',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          SizedBox(height: 4),
          Text(
            '• type 题型：单选/多选/填空/判断/不定项（或 single/multiple/fill/judge/undefined）\n'
            '• stem 题干：支持 Markdown\n'
            '• options 选项：以 || 分隔（如 A. xxx || B. yyy）\n'
            '• answer 答案：单选/判断为索引(0/1)，多选为逗号分隔索引(如 0,2)，填空以 || 分隔多空\n'
            '  （CSV/Excel 中多选答案改用分号 0;2，避免与逗号列分隔冲突）\n'
            '• explanation 解析（可选）\n'
            '• tags 标签（可选，逗号分隔）\n'
            '• difficulty 难度 1-5（可选，默认 3）',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _codeTab(String code, String ext, String filename) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(filename,
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.download, size: 16),
                label: const Text('下载示例'),
                onPressed: () => _download(ext, code),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  code,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12, height: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _download(String ext, String content) async {
    final out = await FilePicker.platform.saveFile(
      dialogTitle: '保存模板',
      fileName: 'starhope_template.$ext',
    );
    if (out == null) return;
    await File(out).writeAsString(content);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已保存：$out')));
    }
  }

  // ============ 示例内容 ============

  static const _csvExample = '''type,stem,options,answer,explanation,tags,difficulty
single,Flutter 使用哪种语言？,A. Java||B. Kotlin||C. Dart||D. Swift,2,Flutter 使用 Dart,Flutter;基础,1
multiple,下列哪些是关系型数据库？,A. MySQL||B. Redis||C. PostgreSQL||D. MongoDB,0;2,Redis 与 MongoDB 为非关系型,数据库,2
judge,SQLite 是轻量级嵌入式数据库。,,1,正确,数据库,1
fill,PBKDF2 的全称是____。,,基于口令的密钥派生函数,,安全,3

提示：
• 多选答案用分号分隔（0;2），勿用逗号（会被当成两列错位）；含逗号的字段也可用英文双引号包裹。
• tags 多标签同样用分号分隔。
• 每行列数必须与表头一致，空值留空（如填空题无选项，options 列留空）。''';

  static const _htmlExample = '''<!DOCTYPE html>
<html><body>
  <div class="question">
    <div class="stem">Flutter 使用哪种语言？</div>
    <ul class="options">
      <li>A. Java</li><li>B. Kotlin</li><li>C. Dart</li><li>D. Swift</li>
    </ul>
    <p>答案: C</p>
    <p>解析: Flutter 使用 Dart 语言。</p>
  </div>
  <!-- 更多题目... -->
</body></html>

提示：导入时可指定 CSS 选择器定位单个题目块（如 .question）。''';

  static const _mdExample = '''---
题型: 单选
题干: Flutter 使用哪种语言？
选项: A. Java || B. Kotlin || C. Dart || D. Swift
答案: C
解析: Flutter 使用 Dart 语言开发。
标签: Flutter, 基础
难度: 1
---
题型: 多选
题干: 下列哪些是关系型数据库？
选项: A. MySQL || B. Redis || C. PostgreSQL || D. MongoDB
答案: A, C
解析: Redis 与 MongoDB 为非关系型。
标签: 数据库
难度: 2
---
题型: 判断
题干: SQLite 是轻量级嵌入式数据库。
答案: 正确
解析: 常嵌入应用中。
标签: 数据库
难度: 1
---
题型: 填空
题干: PBKDF2 的全称是____。
答案: 基于口令的密钥派生函数
标签: 安全
难度: 3
---''';
}

