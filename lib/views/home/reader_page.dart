import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/models/models.dart';
import '../../providers/reader_provider.dart';
import '../common/glass.dart';
import 'reader_viewer_page.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key});
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  @override
  Widget build(BuildContext context) {
    final rd = context.watch<ReaderProvider>();
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('学习资料',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _import,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('导入资料'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: rd.materials.isEmpty
                  ? EmptyState(
                      icon: Icons.menu_book_outlined,
                      title: '暂无学习资料',
                      subtitle: '支持 PDF / DOCX / PPTX / HTML / TXT / Markdown / CSV',
                      action: FilledButton.icon(
                        onPressed: _import,
                        icon: const Icon(Icons.add),
                        label: const Text('导入资料'),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 320,
                        childAspectRatio: 1.4,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: rd.materials.length,
                      itemBuilder: (_, i) =>
                          _materialCard(context, rd, rd.materials[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _materialCard(
      BuildContext context, ReaderProvider rd, ReadingMaterial m) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReaderViewerPage(materialId: m.id)),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_formatIcon(m.format), color: cs.primary, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(m.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (m.finished)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6)),
                      child: const Text('已阅',
                          style: TextStyle(
                              fontSize: 10, color: Colors.green)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (m.isFromShare)
                SourceBadge(nickname: m.sourceNickname, authorId: m.sourceAuthorId),
              const Spacer(),
              LinearProgressIndicator(value: m.progress),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('${(m.sizeBytes / 1024).round()} KB',
                      style:
                          TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('删除资料'),
                          content: Text('确认删除「${m.title}」？'),
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
                      if (ok == true) await rd.deleteMaterial(m.id);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _formatIcon(MaterialFormat f) {
    switch (f) {
      case MaterialFormat.pdf:
        return Icons.picture_as_pdf;
      case MaterialFormat.docx:
        return Icons.description;
      case MaterialFormat.pptx:
        return Icons.slideshow;
      case MaterialFormat.html:
        return Icons.html;
      case MaterialFormat.md:
        return Icons.article;
      case MaterialFormat.csv:
        return Icons.table_chart;
      default:
        return Icons.note;
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf', 'docx', 'doc', 'pptx', 'ppt', 'xlsx', 'xls',
        'html', 'htm', 'txt', 'md', 'markdown', 'csv', 'log',
        'epub', 'odt', 'odp', 'ods', 'rtf'
      ],
    );
    if (result == null || result.files.single.path == null) return;
    if (!mounted) return;
    final rd = context.read<ReaderProvider>();
    try {
      await rd.importMaterial(result.files.single.path!);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('资料已导入')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }
}

// 引用常量避免未使用
// ignore: unused_element
const String _kApp = AppConstants.appName;
