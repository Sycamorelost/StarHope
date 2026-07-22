import 'dart:io';

import 'package:flutter/material.dart';

import '../core/crypto/crypto_service.dart';
import '../core/models/models.dart';
import '../services/database/database.dart';
import '../services/file_storage_service.dart';

/// 阅读器状态 Provider
class ReaderProvider extends ChangeNotifier {
  final AppDatabase _db = AppDatabase.instance;

  List<ReadingMaterial> _materials = [];
  List<ReadingMaterial> get materials => _materials;

  ReadingMaterial? _current;
  List<Note> _currentNotes = [];
  ReadingMaterial? get current => _current;
  List<Note> get currentNotes => _currentNotes;

  Future<void> load() async {
    _materials = await _db.allMaterials();
    notifyListeners();
  }

  /// 导入资料文件到私有目录
  Future<ReadingMaterial> importMaterial(String sourcePath,
      {String? sourceNickname, String? sourceAuthorId}) async {
    final info = await FileStorageService.importFile(sourcePath);
    final title = sourcePath.split(Platform.pathSeparator).last;
    final ext = title.split('.').last;
    final now = DateTime.now().millisecondsSinceEpoch;
    final material = ReadingMaterial(
      id: CryptoService.generateId(),
      title: title,
      format: MaterialFormatX.fromExt(ext),
      storedPath: info.storedPath,
      sizeBytes: info.sizeBytes,
      sourceNickname: sourceNickname,
      sourceAuthorId: sourceAuthorId,
      addedAt: now,
      lastReadAt: now,
    );
    await _db.saveMaterial(material);
    await load();
    return material;
  }

  Future<void> openMaterial(String id) async {
    _current = _materials.firstWhere((m) => m.id == id);
    _currentNotes = await _db.notesOf(id);
    notifyListeners();
  }

  Future<void> updateProgress(String id, double progress, int page) async {
    final m = _materials.firstWhere((e) => e.id == id);
    final finished = progress >= 0.999;
    final updated = ReadingMaterial(
      id: m.id,
      title: m.title,
      format: m.format,
      storedPath: m.storedPath,
      sizeBytes: m.sizeBytes,
      sourceNickname: m.sourceNickname,
      sourceAuthorId: m.sourceAuthorId,
      progress: progress,
      finished: finished,
      addedAt: m.addedAt,
      lastReadAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.saveMaterial(updated);
    _current = updated;
    final idx = _materials.indexWhere((e) => e.id == id);
    if (idx >= 0) _materials[idx] = updated;
    notifyListeners();
  }

  Future<void> deleteMaterial(String id) async {
    final m = _materials.firstWhere((e) => e.id == id);
    await FileStorageService.delete(m.storedPath);
    await _db.deleteMaterial(id);
    if (_current?.id == id) _current = null;
    await load();
  }

  // ============ 笔记 ============
  Future<Note> addNote(Note n) async {
    final note = n.copyWith(
      id: CryptoService.generateId(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.saveNote(note);
    _currentNotes = [..._currentNotes, note];
    notifyListeners();
    return note;
  }

  Future<void> updateNote(Note n) async {
    await _db.saveNote(n);
    _currentNotes = _currentNotes.map((e) => e.id == n.id ? n : e).toList();
    notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    await _db.deleteNote(id);
    _currentNotes = _currentNotes.where((e) => e.id != id).toList();
    notifyListeners();
  }

  /// 单独导出某资料的笔记为 Markdown
  String exportNotesMarkdown() {
    final sb = StringBuffer();
    sb.writeln('# ${_current?.title ?? ''} - 笔记');
    sb.writeln();
    for (final n in _currentNotes) {
      final author = n.isOriginal ? '原始作者${n.sourceNickname != null ? '(${n.sourceNickname})' : ''}' : '我的笔记';
      sb.writeln('## ${_noteTypeLabel(n.type)} · $author');
      if (n.text.isNotEmpty) sb.writeln(n.text);
      if (n.payload.isNotEmpty) sb.writeln('```json\n${n.payload}\n```');
      sb.writeln();
    }
    return sb.toString();
  }

  String _noteTypeLabel(NoteType t) {
    switch (t) {
      case NoteType.highlight:
        return '高亮';
      case NoteType.underline:
        return '下划线';
      case NoteType.drawing:
        return '绘图';
      case NoteType.sticky:
        return '便签';
      case NoteType.bookmark:
        return '书签';
    }
  }
}
