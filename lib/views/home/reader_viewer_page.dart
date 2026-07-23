import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/models/models.dart';
import '../../providers/reader_provider.dart';
import '../common/glass.dart';
import '../common/theme.dart';

/// 一条绘图笔画：关联其持久化 Note 的 id，用于撤回/删除时同步 DB。
class _Stroke {
  final String noteId;
  final List<Offset> points;
  const _Stroke(this.noteId, this.points);
}

/// 一条文本高亮：关联其持久化 Note 的 id + 一组 PDF 文本矩形（PDF 坐标系）。
/// PDF 坐标系原点在左下、Y 轴向上（top >= bottom），与 Flutter 的 Rect（top<=bottom）不同，
/// 故直接用 pdfrx 的 PdfRect 承载（PdfRect 允许 top>bottom）。
class _Highlight {
  final String noteId;
  final List<PdfRect> boxes;
  const _Highlight(this.noteId, this.boxes);
}

class ReaderViewerPage extends StatefulWidget {
  final String materialId;
  const ReaderViewerPage({super.key, required this.materialId});

  @override
  State<ReaderViewerPage> createState() => _ReaderViewerPageState();
}

class _ReaderViewerPageState extends State<ReaderViewerPage> {
  final _pageController = PageController();
  List<String> _pages = [];
  bool _loading = true;
  bool _showNotes = true;
  bool _drawMode = false;
  // 文本路径绘图（按页分组，屏幕绝对坐标；翻页只显示当前页笔画）
  final Map<int, List<_Stroke>> _textStrokesByPage = {};
  // 笔记侧栏按页分组 memo（按 notes 列表身份缓存，避免每帧重算）
  int? _notesGroupKey;
  Map<int, List<Note>>? _notesByPage;
  List<int>? _notesPages;
  List<Offset> _currentStroke = [];
  int _currentPage = 0;
  final _noteText = TextEditingController();
  // 文本路径当前选区（来自 SelectionArea.onSelectionChanged），用于"高亮所选"
  String? _textSelection;

  // PDF 原生渲染路径
  bool _isPdf = false;
  PdfViewerController? _pdfController;
  int _pdfPageCount = 0;
  final Map<int, List<_Stroke>> _pdfStrokesByPage = {}; // key=pageIndex(0-based)，PDF user-space 坐标
  final Map<int, List<_Stroke>> _legacyStrokesByPage = {}; // 占位时期旧笔画（屏幕绝对坐标，无法对齐）
  final Map<int, List<_Highlight>> _pdfHighlightsByPage = {}; // key=pageIndex(0-based)，PDF 坐标矩形
  List<Offset> _currentPdfStroke = []; // 当前绘制中（PDF user-space）
  int _currentDrawPageIndex = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _noteText.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rd = context.read<ReaderProvider>();
    await rd.openMaterial(widget.materialId);
    final m = rd.current!;
    _isPdf = m.format == MaterialFormat.pdf;
    if (_isPdf) {
      try {
        final doc = await PdfDocument.openFile(m.storedPath);
        _pdfPageCount = doc.pages.length;
        await doc.dispose();
        _pdfController = PdfViewerController();
        _currentPage =
            (m.progress * _pdfPageCount).floor().clamp(0, _pdfPageCount - 1);
        _loadPdfStrokes(rd.currentNotes);
        _loadPdfHighlights(rd.currentNotes);
        if (_legacyStrokesByPage.isNotEmpty) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _promptLegacyStrokes());
        }
      } catch (e) {
        _pdfPageCount = 0;
      }
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final text = await _extractText(m);
      _pages = _paginate(text, m.format);
      if (_pages.isEmpty) _pages = ['（无文本内容）'];
      _currentPage = (m.progress * _pages.length).floor().clamp(0, _pages.length - 1);
      _loadTextStrokes(rd.currentNotes);
    } catch (e) {
      _pages = ['加载失败：$e'];
    }
    setState(() => _loading = false);
  }

  /// 从笔记加载 PDF 绘图：按 payload 的 cs 字段区分新（PDF user-space）与旧（屏幕绝对）坐标。
  void _loadPdfStrokes(List<Note> notes) {
    for (final n in notes) {
      if (n.type != NoteType.drawing) continue;
      try {
        final data = jsonDecode(n.payload) as Map<String, dynamic>;
        final page = (data['page'] as num?)?.toInt() ?? n.pageIndex;
        if (data['cs'] == 'pdf') {
          for (final s in (data['strokes'] as List? ?? [])) {
            final pts = (s as List)
                .map((p) => Offset(
                    (p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
                .toList();
            if (pts.isNotEmpty) {
              _pdfStrokesByPage.putIfAbsent(page, () => []).add(_Stroke(n.id, pts));
            }
          }
        } else {
          final pts = (data['points'] as List? ?? [])
              .map((p) => Offset(
                  (p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
              .toList();
          if (pts.isNotEmpty) {
            _legacyStrokesByPage.putIfAbsent(page, () => []).add(_Stroke(n.id, pts));
          }
        }
      } catch (_) {
        // 无法解析的旧笔记忽略
      }
    }
  }

  /// 从笔记加载 PDF 高亮（PDF 坐标矩形）。文本路径高亮无 rects，不进此表（仅留在侧栏）。
  void _loadPdfHighlights(List<Note> notes) {
    for (final n in notes) {
      if (n.type != NoteType.highlight) continue;
      try {
        final data = jsonDecode(n.payload) as Map<String, dynamic>;
        if (data['rects'] == null) continue; // 文本路径高亮无 rects
        final page = (data['page'] as num?)?.toInt() ?? n.pageIndex;
        final rects = (data['rects'] as List)
            .map((e) => PdfRect(
                  (e['l'] as num).toDouble(),
                  (e['t'] as num).toDouble(),
                  (e['r'] as num).toDouble(),
                  (e['b'] as num).toDouble()))
            .toList();
        if (rects.isNotEmpty) {
          _pdfHighlightsByPage.putIfAbsent(page, () => []).add(_Highlight(n.id, rects));
        }
      } catch (_) {
        // 无法解析的旧笔记忽略
      }
    }
  }

  /// 文本路径：加载已有绘图笔记（按页分组，屏幕绝对坐标）。
  void _loadTextStrokes(List<Note> notes) {
    for (final n in notes) {
      if (n.type != NoteType.drawing) continue;
      try {
        final data = jsonDecode(n.payload) as Map<String, dynamic>;
        final page = (data['page'] as num?)?.toInt() ?? n.pageIndex;
        final pts = (data['points'] as List? ?? [])
            .map((p) => Offset(
                (p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
            .toList();
        if (pts.isNotEmpty) {
          _textStrokesByPage.putIfAbsent(page, () => []).add(_Stroke(n.id, pts));
        }
      } catch (_) {}
    }
  }

  /// 提取文本：TXT/MD/CSV/HTML/DOCX/PPTX 等（PDF 走原生渲染路径，不调用此方法）。
  Future<String> _extractText(ReadingMaterial m) async {
    final bytes = await File(m.storedPath).readAsBytes();
    switch (m.format) {
      case MaterialFormat.txt:
      case MaterialFormat.md:
      case MaterialFormat.csv:
        return utf8.decode(bytes, allowMalformed: true);
      case MaterialFormat.html:
        final doc = html_parser.parse(utf8.decode(bytes, allowMalformed: true));
        return doc.body?.text ?? '';
      case MaterialFormat.docx:
        return _extractOffice(bytes, 'word/document.xml');
      case MaterialFormat.pptx:
        final archive = ZipDecoder().decodeBytes(bytes);
        final parts = <String>[];
        for (var i = 1; i <= 99; i++) {
          final f = archive.findFile('ppt/slides/slide$i.xml');
          if (f == null) break;
          parts.add(_stripXml(utf8.decode(f.content as List<int>)));
        }
        return parts.join('\n\n---\n\n');
      case MaterialFormat.xlsx:
        return _extractXlsx(bytes);
      case MaterialFormat.epub:
        return _extractEpub(bytes);
      case MaterialFormat.odt:
        return _extractOffice(bytes, 'content.xml');
      case MaterialFormat.odp:
        return _extractOdf(bytes, 'presentation');
      case MaterialFormat.ods:
        return _extractOdf(bytes, 'spreadsheet');
      case MaterialFormat.rtf:
        return _extractRtf(utf8.decode(bytes, allowMalformed: true));
      case MaterialFormat.pdf:
        return '【PDF 文档】\n'
            '本机桌面端已加载该 PDF，可在此页添加便签、高亮与绘图笔记，进度与批注自动保存到本地。\n'
            '（如需逐页图像渲染，可后续接入 PDF 原生渲染模块。）\n\n'
            '文件：${m.title}（${(m.sizeBytes / 1024).round()} KB）';
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  String _extractOffice(List<int> bytes, String innerPath) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final f = archive.findFile(innerPath);
    if (f == null) return '（无法读取文档结构）';
    return _stripXml(utf8.decode(f.content as List<int>));
  }

  /// XLSX：读取共享字符串 + 各工作表的单元格，按行输出。
  String _extractXlsx(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final shared = <String>[];
    final ss = archive.findFile('xl/sharedStrings.xml');
    if (ss != null) {
      for (final m in RegExp(r'<t[^>]*>([^<]*)</t>')
          .allMatches(utf8.decode(ss.content as List<int>))) {
        shared.add(_decodeEntities(m.group(1)!));
      }
    }
    final sheets = <String>[];
    for (var i = 1; i <= 20; i++) {
      final f = archive.findFile('xl/worksheets/sheet$i.xml');
      if (f == null) break;
      final xml = utf8.decode(f.content as List<int>);
      final rowsOut = <String>[];
      for (final rowMatch in RegExp(r'<row[^>]*>(.*?)</row>', dotAll: true)
          .allMatches(xml)) {
        final cells = <String>[];
        for (final c in RegExp(
                r'<c[^>]*?(?:\st="(\w+)")?[^>]*>(?:<v>([^<]*)</v>)?')
            .allMatches(rowMatch.group(1)!)) {
          final type = c.group(1);
          final value = c.group(2) ?? '';
          if (type == 's') {
            cells.add(shared[int.tryParse(value) ?? 0]);
          } else {
            cells.add(_decodeEntities(value));
          }
        }
        if (cells.any((e) => e.isNotEmpty)) rowsOut.add(cells.join('\t'));
      }
      if (rowsOut.isNotEmpty) sheets.add(rowsOut.join('\n'));
    }
    return sheets.isEmpty ? '（无可读工作表）' : sheets.join('\n\n---\n\n');
  }

  /// EPUB：读取 OPS/OEBPS 下各 HTML/xhtml 章节并提取正文。
  String _extractEpub(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final chapters = <String>[];
    for (final f in archive) {
      final n = f.name.toLowerCase();
      if ((n.endsWith('.html') || n.endsWith('.xhtml') || n.endsWith('.htm')) &&
          !n.contains('toc') && !n.contains('nav') && !n.contains('cover')) {
        final text = html_parser
            .parse(utf8.decode(f.content as List<int>))
            .body
            ?.text;
        if (text != null && text.trim().isNotEmpty) chapters.add(text.trim());
      }
    }
    return chapters.isEmpty
        ? '（无法解析 EPUB 章节）'
        : chapters.join('\n\n---\n\n');
  }

  /// ODF（odp/ods）：遍历 content.xml 中的段落/表格行。
  String _extractOdf(List<int> bytes, String kind) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final f = archive.findFile('content.xml');
    if (f == null) return '（无法读取 ODF 结构）';
    var xml = utf8.decode(f.content as List<int>);
    xml = xml
        .replaceAll(RegExp(r'</text:p>'), '\n')
        .replaceAll(RegExp(r'</table:table-row>'), '\n');
    return _decodeEntities(xml.replaceAll(RegExp(r'<[^>]+>'), ''))
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// RTF：剥离控制字与花括号，保留可见文本。
  String _extractRtf(String src) {
    var s = src;
    // 移除 Unicode 转义 \uN? -> 取 N 对应字符
    s = s.replaceAllMapped(RegExp(r'\\u(-?\d+)\??'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)));
    // 移除十六进制字节 \'xx
    s = s.replaceAll(RegExp(r"\\'[0-9a-fA-F]{2}"), '');
    // 移除控制字 \word
    s = s.replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '');
    // 移除剩余反斜杠命令与花括号
    s = s.replaceAll(RegExp(r'[\\{}]'), '');
    return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  String _stripXml(String xml) {
    // 段落与换行处理
    xml = xml
        .replaceAll(RegExp(r'</w:p>'), '\n')
        .replaceAll(RegExp(r'</a:p>'), '\n')
        .replaceAll(RegExp(r'<br\s*/?>'), '\n');
    final text = xml.replaceAll(RegExp(r'<[^>]+>'), '');
    return _decodeEntities(text).replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  String _decodeEntities(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ');

  List<String> _paginate(String text, MaterialFormat fmt) {
    if (text.isEmpty) return const [];
    // 按字符量分页（约 1200 字/页）
    const chunkSize = 1200;
    final pages = <String>[];
    var i = 0;
    while (i < text.length) {
      var end = (i + chunkSize).clamp(0, text.length);
      // 尽量在换行处切分
      if (end < text.length) {
        final nl = text.lastIndexOf('\n', end);
        if (nl > i + chunkSize ~/ 2) end = nl + 1;
      }
      pages.add(text.substring(i, end));
      i = end;
    }
    return pages;
  }

  bool get _canUndo {
    if (_isPdf) return (_pdfStrokesByPage[_currentPage]?.isNotEmpty) ?? false;
    return (_textStrokesByPage[_currentPage]?.isNotEmpty) ?? false;
  }

  bool get _canClear => _canUndo;

  /// 跳转到指定页（PDF 用 PdfViewerController，文本用 PageController）。
  void _jumpToPage(int page) {
    if (_isPdf) {
      _pdfController?.goToPage(pageNumber: page + 1);
    } else {
      _pageController.jumpToPage(page);
    }
    setState(() => _currentPage = page);
  }

  /// 撤销当前页最后一笔（内存 + DB Note 同步删除）。
  Future<void> _undo() async {
    final rd = context.read<ReaderProvider>();
    if (_isPdf) {
      final list = _pdfStrokesByPage[_currentPage];
      if (list == null || list.isEmpty) return;
      final noteId = list.last.noteId;
      setState(() {
        list.removeLast();
        if (list.isEmpty) _pdfStrokesByPage.remove(_currentPage);
      });
      await rd.deleteNote(noteId);
    } else {
      final list = _textStrokesByPage[_currentPage];
      if (list == null || list.isEmpty) return;
      final noteId = list.last.noteId;
      setState(() {
        list.removeLast();
        if (list.isEmpty) _textStrokesByPage.remove(_currentPage);
      });
      await rd.deleteNote(noteId);
    }
  }

  /// 清空当前页全部绘图（内存 + DB Note 同步删除）。
  Future<void> _clearDrawing() async {
    final rd = context.read<ReaderProvider>();
    final ids = <String>[];
    setState(() {
      if (_isPdf) {
        final list = _pdfStrokesByPage.remove(_currentPage);
        if (list != null) ids.addAll(list.map((s) => s.noteId));
        _currentPdfStroke = [];
      } else {
        final list = _textStrokesByPage.remove(_currentPage);
        if (list != null) ids.addAll(list.map((s) => s.noteId));
        _currentStroke = [];
      }
    });
    for (final id in ids) {
      await rd.deleteNote(id);
    }
  }

  /// 删除单条笔记（侧栏触发）：删 DB + 同步移除内存中对应笔画/高亮。
  Future<void> _deleteNote(Note n) async {
    final rd = context.read<ReaderProvider>();
    await rd.deleteNote(n.id);
    if (!mounted) return;
    setState(() {
      _pdfStrokesByPage.forEach(
          (_, list) => list.removeWhere((s) => s.noteId == n.id));
      _pdfStrokesByPage.removeWhere((_, list) => list.isEmpty);
      _textStrokesByPage.forEach(
          (_, list) => list.removeWhere((s) => s.noteId == n.id));
      _textStrokesByPage.removeWhere((_, list) => list.isEmpty);
      _pdfHighlightsByPage.forEach(
          (_, list) => list.removeWhere((h) => h.noteId == n.id));
      _pdfHighlightsByPage.removeWhere((_, list) => list.isEmpty);
      _legacyStrokesByPage.forEach(
          (_, list) => list.removeWhere((s) => s.noteId == n.id));
      _legacyStrokesByPage.removeWhere((_, list) => list.isEmpty);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rd = context.watch<ReaderProvider>();
    final m = rd.current;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: m?.title ?? '阅读',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: _showNotes ? '隐藏笔记' : '显示笔记',
            icon: Icon(_showNotes
                ? Icons.menu_book_outlined
                : Icons.view_sidebar_outlined),
            onPressed: () => setState(() => _showNotes = !_showNotes),
          ),
          IconButton(
            tooltip: '绘图',
            icon: Icon(_drawMode ? Icons.draw : Icons.draw_outlined,
                color: _drawMode
                    ? Theme.of(context).colorScheme.primary
                    : null),
            onPressed: () => setState(() => _drawMode = !_drawMode),
          ),
          if (_drawMode) ...[
            IconButton(
              tooltip: '撤销',
              icon: const Icon(Icons.undo),
              onPressed: _canUndo ? _undo : null,
            ),
            IconButton(
              tooltip: _isPdf ? '清空本页绘图' : '清空本页绘图',
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: _canClear ? _clearDrawing : null,
            ),
          ],
          // 文本路径：高亮当前选中文本（PDF 走右键上下文菜单）
          if (!_isPdf)
            IconButton(
              tooltip: '高亮所选文本',
              icon: const Icon(Icons.highlight),
              onPressed: (_textSelection != null && _textSelection!.trim().isNotEmpty)
                  ? _saveTextHighlight
                  : null,
            ),
          IconButton(
            tooltip: '添加便签',
            icon: const Icon(Icons.sticky_note_2_outlined),
            onPressed: () => _addSticky(),
          ),
          IconButton(
            tooltip: '书签（标记当前页）',
            icon: const Icon(Icons.bookmark_border),
            onPressed: () => _addBookmark(rd),
          ),
          IconButton(
            tooltip: '导出笔记',
            icon: const Icon(Icons.ios_share),
            onPressed: () => _exportNotes(),
          ),
        ],
      ),
      body: FrostedBackground(
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Row(
                  children: [
                    Expanded(child: _readerView(context, rd)),
                    if (_showNotes)
                      SizedBox(width: 320, child: _notesSidebar(context, rd)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _readerView(BuildContext context, ReaderProvider rd) {
    if (_isPdf) return _pdfReaderView(context, rd);
    return _textReaderView(context, rd);
  }

  /// 文本路径：PageView 翻页渲染 Text/Markdown（原逻辑）。
  Widget _textReaderView(BuildContext context, ReaderProvider rd) {
    final m = rd.current!;
    final isMarkdown = m.format == MaterialFormat.md;
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: _pages.length,
          onPageChanged: (i) {
            setState(() {
              _currentPage = i;
              _textSelection = null; // 翻页清空选区
            });
            rd.updateProgress(m.id, (i + 1) / _pages.length, i);
          },
          itemBuilder: (_, i) {
            return Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: isMarkdown
                  ? SingleChildScrollView(
                      child: MarkdownBody(
                          data: _pages[i], selectable: true),
                    )
                  : SelectionArea(
                      onSelectionChanged: (c) {
                        // 仅记录当前页选中文本（无偏移，无法做黄底，存为高亮笔记）
                        setState(() => _textSelection = c?.plainText);
                      },
                      child: SingleChildScrollView(
                        child: Text(
                          _pages[i],
                          style: const TextStyle(
                              fontSize: 15, height: 1.7),
                        ),
                      ),
                    ),
            );
          },
        ),
        // 绘图层（屏幕绝对坐标，仅渲染当前页笔画 → 翻页跟随、回页重现）
        if (_drawMode)
          GestureDetector(
            onPanStart: (_) => _currentStroke = [],
            onPanUpdate: (d) {
              setState(() => _currentStroke = [..._currentStroke, d.localPosition]);
            },
            onPanEnd: (_) {
              if (_currentStroke.length > 1) {
                final pts = List<Offset>.from(_currentStroke);
                setState(() => _currentStroke = []);
                _saveTextStroke(pts);
              } else {
                setState(() => _currentStroke = []);
              }
            },
            child: CustomPaint(
              painter: _DrawingPainter(
                  _textStrokesByPage[_currentPage] ?? const [],
                  _currentStroke,
                  Theme.of(context).colorScheme.primary),
              child: Container(),
            ),
          ),
        // 页码
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Center(
            child: GlassCard(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                  '${_currentPage + 1} / ${_pages.length}    '
                  '${((_currentPage + 1) / _pages.length * 100).round()}%',
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
        ),
        if (m.isFromShare)
          Positioned(
            top: 12,
            right: 16,
            child: SourceBadge(
                nickname: m.sourceNickname, authorId: m.sourceAuthorId),
          ),
      ],
    );
  }

  /// PDF 路径：pdfrx PdfViewer（内置连续滚动 + 缩放）+ 文本选区高亮 + 页码 + 来源徽章。
  Widget _pdfReaderView(BuildContext context, ReaderProvider rd) {
    final m = rd.current!;
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        PdfViewer.file(
          m.storedPath,
          controller: _pdfController,
          initialPageNumber: _currentPage + 1,
          params: _buildPdfParams(context, rd, cs),
        ),
        if (_pdfPageCount > 0)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: GlassCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                    '${_currentPage + 1} / $_pdfPageCount    '
                    '${((_currentPage + 1) / _pdfPageCount * 100).round()}%',
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
          ),
        if (m.isFromShare)
          Positioned(
            top: 12,
            right: 16,
            child: SourceBadge(
                nickname: m.sourceNickname, authorId: m.sourceAuthorId),
          ),
      ],
    );
  }

  /// 根据 _drawMode 切换两套 PdfViewerParams：绘图时关 pan/scale，叠加层接管手势。
  /// 非绘图模式开启文本选区 + 右键"高亮"上下文菜单。
  PdfViewerParams _buildPdfParams(
      BuildContext context, ReaderProvider rd, ColorScheme cs) {
    final m = rd.current!;
    if (_drawMode) {
      return PdfViewerParams(
        panEnabled: false,
        scaleEnabled: false,
        pageOverlaysBuilder: (ctx, pageRect, page) => [
          _pdfHighlightOverlay(pageRect, page),
          _pdfDrawingOverlay(pageRect, page, cs),
        ],
      );
    }
    return PdfViewerParams(
      panEnabled: true,
      scaleEnabled: true,
      textSelectionParams: const PdfTextSelectionParams(enabled: true),
      customizeContextMenuItems: _customizePdfSelectionMenu,
      onPageChanged: (n) {
        if (n == null) return;
        setState(() => _currentPage = n - 1);
        rd.updateProgress(m.id, n / _pdfPageCount, n - 1);
      },
      pageOverlaysBuilder: (ctx, pageRect, page) => [
        _pdfHighlightOverlay(pageRect, page),
        _pdfReadOnlyOverlay(pageRect, page, cs),
      ],
    );
  }

  /// PDF 选中文本后的上下文菜单：在默认项（复制/全选）后追加"高亮"按钮。
  void _customizePdfSelectionMenu(
      PdfViewerContextMenuBuilderParams params, List<ContextMenuButtonItem> items) {
    final delegate = params.textSelectionDelegate;
    if (!params.isTextSelectionEnabled || !delegate.hasSelectedText) return;
    items.add(ContextMenuButtonItem(
      type: ContextMenuButtonType.custom,
      label: '高亮',
      onPressed: () async {
        final ranges = await delegate.getSelectedTextRanges();
        params.dismissContextMenu();
        await delegate.clearTextSelection();
        if (!mounted) return;
        await _savePdfHighlights(ranges);
      },
    ));
  }

  /// 每页绘图叠加层（绘图模式）：采集 PDF user-space 坐标 + 实时绘制。
  Widget _pdfDrawingOverlay(Rect pageRect, PdfPage page, ColorScheme cs) {
    final pageIndex = page.pageNumber - 1;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (d) {
        _currentDrawPageIndex = pageIndex;
        _currentPdfStroke = [_localToPdf(d.localPosition, pageRect, page)];
      },
      onPanUpdate: (d) {
        setState(() {
          _currentDrawPageIndex = pageIndex;
          _currentPdfStroke = [
            ..._currentPdfStroke,
            _localToPdf(d.localPosition, pageRect, page),
          ];
        });
      },
      onPanEnd: (_) {
        if (_currentPdfStroke.length > 1) {
          final pts = List<Offset>.from(_currentPdfStroke);
          final pageIdx = pageIndex;
          setState(() {
            _currentPdfStroke = [];
            _currentDrawPageIndex = -1;
          });
          _savePdfStroke(pageIdx, pts);
        } else {
          setState(() {
            _currentPdfStroke = [];
            _currentDrawPageIndex = -1;
          });
        }
      },
      child: CustomPaint(
        size: pageRect.size,
        painter: _PdfStrokePainter(
          _pdfStrokesByPage[pageIndex] ?? const [],
          _currentDrawPageIndex == pageIndex ? _currentPdfStroke : const [],
          page,
          cs.primary,
        ),
        child: SizedBox(width: pageRect.width, height: pageRect.height),
      ),
    );
  }

  /// 每页只读叠加层（非绘图模式）：仅显示已保存笔画，透传手势给 viewer。
  Widget _pdfReadOnlyOverlay(Rect pageRect, PdfPage page, ColorScheme cs) {
    final pageIndex = page.pageNumber - 1;
    final strokes = _pdfStrokesByPage[pageIndex] ?? const [];
    if (strokes.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: pageRect.size,
        painter: _PdfStrokePainter(strokes, const [], page, cs.primary),
        child: SizedBox(width: pageRect.width, height: pageRect.height),
      ),
    );
  }

  /// 每页高亮叠加层（只读 IgnorePointer，两种模式都渲染）。
  Widget _pdfHighlightOverlay(Rect pageRect, PdfPage page) {
    final pageIndex = page.pageNumber - 1;
    final hs = _pdfHighlightsByPage[pageIndex] ?? const [];
    if (hs.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: pageRect.size,
        painter: _PdfHighlightPainter(hs, page),
        child: SizedBox(width: pageRect.width, height: pageRect.height),
      ),
    );
  }

  /// 叠加层局部坐标 → PDF user-space 坐标（线性映射，随缩放自洽）。
  Offset _localToPdf(Offset local, Rect pageRect, PdfPage page) {
    return Offset(
      local.dx / pageRect.width * page.width,
      local.dy / pageRect.height * page.height,
    );
  }

  /// 文本路径：保存一笔绘图（屏幕绝对坐标）→ 拿 Note id 加入当前页内存。
  Future<void> _saveTextStroke(List<Offset> points) async {
    final rd = context.read<ReaderProvider>();
    final note = await rd.addNote(Note(
      id: '',
      materialId: widget.materialId,
      type: NoteType.drawing,
      pageIndex: _currentPage,
      payload: jsonEncode({
        'page': _currentPage,
        'points': points.map((o) => {'x': o.dx, 'y': o.dy}).toList(),
      }),
      isOriginal: false,
      createdAt: 0,
    ));
    if (!mounted) return;
    setState(() {
      _textStrokesByPage.putIfAbsent(_currentPage, () => []).add(_Stroke(note.id, points));
    });
  }

  /// 文本路径：把当前选中文本存为高亮笔记（无视觉黄底，仅在侧栏展示 + 跳转）。
  Future<void> _saveTextHighlight() async {
    final text = _textSelection?.trim() ?? '';
    if (text.isEmpty) return;
    final rd = context.read<ReaderProvider>();
    await rd.addNote(Note(
      id: '',
      materialId: widget.materialId,
      type: NoteType.highlight,
      pageIndex: _currentPage,
      payload: jsonEncode({'page': _currentPage}), // 文本高亮无 rects
      text: text,
      isOriginal: false,
      createdAt: 0,
    ));
    if (!mounted) return;
    setState(() => _textSelection = null);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已高亮（第 ${_currentPage + 1} 页）')));
  }

  /// PDF 路径：保存一笔绘图（PDF user-space 坐标）→ 拿 Note id 加入内存。
  Future<void> _savePdfStroke(int pageIndex, List<Offset> points) async {
    final rd = context.read<ReaderProvider>();
    final note = await rd.addNote(Note(
      id: '',
      materialId: widget.materialId,
      type: NoteType.drawing,
      pageIndex: pageIndex,
      payload: jsonEncode({
        'version': 2,
        'cs': 'pdf',
        'page': pageIndex,
        'strokes': [points.map((o) => {'x': o.dx, 'y': o.dy}).toList()],
      }),
      isOriginal: false,
      createdAt: 0,
    ));
    if (!mounted) return;
    setState(() {
      _pdfStrokesByPage.putIfAbsent(pageIndex, () => []).add(_Stroke(note.id, points));
    });
  }

  /// PDF 路径：把选中文本范围存为高亮（PDF 坐标矩形，可逐页黄色叠加渲染）。
  Future<void> _savePdfHighlights(List<PdfPageTextRange> ranges) async {
    if (ranges.isEmpty) return;
    final rd = context.read<ReaderProvider>();
    var saved = 0;
    for (final range in ranges) {
      final page = range.pageNumber - 1;
      final boxes = <PdfRect>[];
      final charRects = range.pageText.charRects;
      for (var i = range.start; i < range.end; i++) {
        if (i >= 0 && i < charRects.length) boxes.add(charRects[i]);
      }
      if (boxes.isEmpty) continue;
      final note = await rd.addNote(Note(
        id: '',
        materialId: widget.materialId,
        type: NoteType.highlight,
        pageIndex: page,
        payload: jsonEncode({
          'page': page,
          'rects': boxes
              .map((r) => {'l': r.left, 't': r.top, 'r': r.right, 'b': r.bottom})
              .toList(),
        }),
        text: range.text,
        isOriginal: false,
        createdAt: 0,
      ));
      if (!mounted) return;
      setState(() {
        _pdfHighlightsByPage.putIfAbsent(page, () => []).add(_Highlight(note.id, boxes));
      });
      saved++;
    }
    if (mounted && saved > 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已高亮 $saved 处')));
    }
  }

  /// 旧数据兼容：检测到占位时期旧绘图（无法与新渲染对齐），一次性询问清除。
  void _promptLegacyStrokes() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('检测到旧绘图笔记'),
        content: const Text(
            '此 PDF 在占位渲染时期存有绘图笔记，已无法与新渲染对齐。是否清除这些旧笔记？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('保留（隐藏）')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearLegacyStrokes();
            },
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }

  void _clearLegacyStrokes() async {
    final rd = context.read<ReaderProvider>();
    final ids = <String>[];
    for (final list in _legacyStrokesByPage.values) {
      ids.addAll(list.map((s) => s.noteId));
    }
    for (final id in ids) {
      await rd.deleteNote(id);
    }
    if (mounted) setState(() => _legacyStrokesByPage.clear());
  }

  Future<void> _addSticky() async {
    _noteText.clear();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加便签'),
        content: TextField(
          controller: _noteText,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入笔记内容…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _noteText.text),
            child: const Text('保存')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    if (!mounted) return;
    await context.read<ReaderProvider>().addNote(Note(
      id: '',
      materialId: widget.materialId,
      type: NoteType.sticky,
      pageIndex: _currentPage,
      payload: jsonEncode({'page': _currentPage}),
      text: text,
      isOriginal: false,
      createdAt: 0,
    ));
  }

  Future<void> _exportNotes() async {
    final rd = context.read<ReaderProvider>();
    final md = rd.exportNotesMarkdown();
    final out = await FilePicker.platform.saveFile(
      dialogTitle: '导出笔记',
      fileName: '${rd.current?.title ?? 'notes'}.md',
    );
    if (out == null) return;
    await File(out).writeAsString(md);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已导出：$out')));
    }
  }

  Widget _notesSidebar(BuildContext context, ReaderProvider rd) {
    final notes = rd.currentNotes;
    // 按页分组（memo：notes 列表身份不变则复用，避免每帧重算分组+排序）
    if (_notesGroupKey != identityHashCode(notes)) {
      _notesGroupKey = identityHashCode(notes);
      final byPage = <int, List<Note>>{};
      for (final n in notes) {
        byPage.putIfAbsent(n.pageIndex, () => []).add(n);
      }
      _notesByPage = byPage;
      _notesPages = byPage.keys.toList()..sort();
    }
    final byPage = _notesByPage!;
    final pages = _notesPages!;
    return GlassCard(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('笔记 (${notes.length})',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          const Divider(height: 1),
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                          _isPdf
                              ? '暂无笔记\n选中正文可右键高亮，或开启绘图 / 添加便签 / 书签'
                              : '暂无笔记\n选中正文点高亮，或开启绘图 / 添加便签 / 书签',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                  )
                : ListView.builder(
                    itemCount: pages.length,
                    itemBuilder: (_, i) {
                      final page = pages[i];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: InkWell(
                              onTap: () => _jumpToPage(page),
                              child: Text('第 ${page + 1} 页',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                          for (final n in byPage[page]!)
                            _noteTile(context, rd, n),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _noteTile(BuildContext context, ReaderProvider rd, Note n) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _jumpToPage(n.pageIndex),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.tertiaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_noteIcon(n.type), size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (n.text.isNotEmpty)
                    Text(n.text,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                  if (n.type == NoteType.drawing)
                    Text('绘图笔记', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  Text(n.isOriginal ? '原始作者${n.sourceNickname != null ? '·${n.sourceNickname}' : ''}' : '我的笔记',
                      style: TextStyle(
                          fontSize: 10, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              tooltip: '删除',
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
              onPressed: () => _deleteNote(n),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addBookmark(ReaderProvider rd) async {
    await rd.addNote(Note(
      id: '',
      materialId: widget.materialId,
      type: NoteType.bookmark,
      pageIndex: _currentPage,
      payload: jsonEncode({'page': _currentPage}),
      text: '第 ${_currentPage + 1} 页',
      isOriginal: false,
      createdAt: 0,
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加书签：第 ${_currentPage + 1} 页')));
  }

  IconData _noteIcon(NoteType t) {
    switch (t) {
      case NoteType.highlight:
        return Icons.highlight;
      case NoteType.underline:
        return Icons.format_underlined;
      case NoteType.drawing:
        return Icons.draw;
      case NoteType.sticky:
        return Icons.sticky_note_2;
      case NoteType.bookmark:
        return Icons.bookmark_border;
    }
  }
}

/// 文本路径绘图绘制器（屏幕绝对坐标）。
class _DrawingPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final List<Offset> current;
  final Color color;
  _DrawingPainter(this.strokes, this.current, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final stroke in strokes) {
      for (var i = 0; i < stroke.points.length - 1; i++) {
        canvas.drawLine(stroke.points[i], stroke.points[i + 1], paint);
      }
    }
    for (var i = 0; i < current.length - 1; i++) {
      canvas.drawLine(current[i], current[i + 1], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter old) => true;
}

/// PDF 路径绘图绘制器：笔画存 PDF user-space 坐标，绘制时按 size/page 尺寸变换对齐。
class _PdfStrokePainter extends CustomPainter {
  final List<_Stroke> strokes; // PDF user-space 坐标
  final List<Offset> current; // PDF user-space 坐标（绘制中）
  final PdfPage page;
  final Color color;
  _PdfStrokePainter(this.strokes, this.current, this.page, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (page.width == 0 || page.height == 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final sx = size.width / page.width;
    final sy = size.height / page.height;
    void drawStroke(List<Offset> stroke) {
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(
          Offset(stroke[i].dx * sx, stroke[i].dy * sy),
          Offset(stroke[i + 1].dx * sx, stroke[i + 1].dy * sy),
          paint,
        );
      }
    }
    for (final s in strokes) {
      drawStroke(s.points);
    }
    drawStroke(current);
  }

  @override
  bool shouldRepaint(covariant _PdfStrokePainter old) => true;
}

/// PDF 路径高亮绘制器：矩形存 PDF 坐标（原点左下、Y 向上），绘制时翻转 Y 轴 + 旋转变换对齐。
class _PdfHighlightPainter extends CustomPainter {
  final List<_Highlight> highlights;
  final PdfPage page;
  _PdfHighlightPainter(this.highlights, this.page);

  @override
  void paint(Canvas canvas, Size size) {
    if (page.width == 0 || page.height == 0) return;
    final paint = Paint()
      // 半透明高亮黄（与正文叠加，可读性保留）
      ..color = const Color(0x55FFC107)
      ..style = PaintingStyle.fill;
    final sx = size.width / page.width;
    final sy = size.height / page.height;
    final ph = page.height;
    for (final h in highlights) {
      for (final box in h.boxes) {
        // charRects 为未旋转 PDF 坐标，按 page.rotation 旋转到显示坐标系
        final r = page.rotation.index == 0 ? box : box.rotate(page.rotation.index, page);
        // PDF 坐标（原点左下、Y 向上）→ 叠加层坐标（原点左上、Y 向下）
        canvas.drawRect(
          Rect.fromLTRB(
            r.left * sx,
            (ph - r.top) * sy,
            r.right * sx,
            (ph - r.bottom) * sy,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PdfHighlightPainter old) => true;
}

// 引用常量
// ignore: unused_element
const String _kApp = AppConstants.appName;
