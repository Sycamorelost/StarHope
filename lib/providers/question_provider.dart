import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/crypto/crypto_service.dart';
import '../core/models/models.dart';
import '../core/models/question.dart';
import '../services/database/database.dart';
import '../services/question_import_service.dart';

/// 题库排序方式
enum QuestionSortBy {
  updatedDesc, // 最近更新
  createdDesc, // 最近创建
  difficultyDesc, // 难度优先
  accuracyAsc, // 正确率升序（薄弱优先）
  practicedAsc, // 最久未练优先
  practicedDesc, // 最近练习优先
}

/// 题目正确率（被练过才有意义；未练返回 -1）。
double questionAccuracy(Question q) =>
    q.practiceCount > 0 ? q.correctCount / q.practiceCount : -1;

/// 题库状态 Provider
class QuestionBankProvider extends ChangeNotifier {
  final AppDatabase _db = AppDatabase.instance;
  final QuestionImportService _import = QuestionImportService();

  List<Question> _all = [];
  List<Question> _filtered = [];
  List<String> _tags = [];
  List<String> _sources = [];
  List<QuestionFolder> _folders = [];
  String? _currentFolderId; // 题库页当前所在夹（null = 根）

  // 筛选状态
  String _keyword = '';
  List<QuestionType> _typeFilter = [];
  List<String> _tagFilter = [];
  String? _sourceFilter;
  QuestionSortBy _sortBy = QuestionSortBy.updatedDesc;
  bool _weakOnly = false; // 仅薄弱（正确率<60% 且已练过）

  List<Question> get questions => _filtered;
  List<String> get tags => _tags;
  List<String> get sources => _sources;
  List<QuestionFolder> get folders => _folders;
  String? get currentFolderId => _currentFolderId;
  String get keyword => _keyword;
  List<QuestionType> get typeFilter => _typeFilter;
  List<String> get tagFilter => _tagFilter;
  String? get sourceFilter => _sourceFilter;
  QuestionSortBy get sortBy => _sortBy;
  bool get weakOnly => _weakOnly;

  Future<void> load() async {
    _all = await _db.allQuestions();
    _tags = await _db.allTags();
    _sources = await _db.allSources();
    _folders = await _db.allFolders();
    _applyFilter();
    notifyListeners();
  }

  void setKeyword(String k) {
    _keyword = k;
    _applyFilter();
    notifyListeners();
  }

  void toggleType(QuestionType t) {
    if (_typeFilter.contains(t)) {
      _typeFilter = _typeFilter.where((e) => e != t).toList();
    } else {
      _typeFilter = [..._typeFilter, t];
    }
    _applyFilter();
    notifyListeners();
  }

  void toggleTag(String t) {
    if (_tagFilter.contains(t)) {
      _tagFilter = _tagFilter.where((e) => e != t).toList();
    } else {
      _tagFilter = [..._tagFilter, t];
    }
    _applyFilter();
    notifyListeners();
  }

  void setSource(String? s) {
    _sourceFilter = s;
    _applyFilter();
    notifyListeners();
  }

  void setSort(QuestionSortBy s) {
    _sortBy = s;
    _applyFilter();
    notifyListeners();
  }

  void setWeakOnly(bool v) {
    _weakOnly = v;
    _applyFilter();
    notifyListeners();
  }

  void clearFilter() {
    _keyword = '';
    _typeFilter = [];
    _tagFilter = [];
    _sourceFilter = null;
    _weakOnly = false;
    _applyFilter();
    notifyListeners();
  }

  void _applyFilter() {
    _filtered = _all.where((q) {
      if (_currentFolderId != null && q.folderId != _currentFolderId) {
        return false;
      }
      if (_keyword.isNotEmpty &&
          !q.stem.toLowerCase().contains(_keyword.toLowerCase()) &&
          !q.explanation.toLowerCase().contains(_keyword.toLowerCase())) {
        return false;
      }
      if (_typeFilter.isNotEmpty && !_typeFilter.contains(q.type)) {
        return false;
      }
      if (_tagFilter.isNotEmpty &&
          !_tagFilter.any((t) => q.tags.contains(t))) {
        return false;
      }
      if (_sourceFilter != null &&
          q.sourceNickname != _sourceFilter) {
        return false;
      }
      if (_weakOnly) {
        final acc = questionAccuracy(q);
        if (acc < 0 || acc >= 0.6) return false; // 仅保留已练且正确率<60%
      }
      return true;
    }).toList();
    _filtered.sort((a, b) {
      switch (_sortBy) {
        case QuestionSortBy.createdDesc:
          return b.createdAt.compareTo(a.createdAt);
        case QuestionSortBy.updatedDesc:
          return b.updatedAt.compareTo(a.updatedAt);
        case QuestionSortBy.difficultyDesc:
          return b.difficulty.compareTo(a.difficulty);
        case QuestionSortBy.accuracyAsc:
          // 正确率低优先；未练（-1）排最后
          final aa = questionAccuracy(a), ab = questionAccuracy(b);
          if (aa < 0 && ab < 0) return 0;
          if (aa < 0) return 1;
          if (ab < 0) return -1;
          return aa.compareTo(ab);
        case QuestionSortBy.practicedAsc:
          // 最久未练优先：未练/null 视为最久 → 排最前
          final ta = a.lastPracticedAt ?? -1;
          final tb = b.lastPracticedAt ?? -1;
          return ta.compareTo(tb);
        case QuestionSortBy.practicedDesc:
          final ta = a.lastPracticedAt ?? 0;
          final tb = b.lastPracticedAt ?? 0;
          return tb.compareTo(ta);
      }
    });
  }

  QuestionFilter toFilter({bool wrongFirst = false, int? limit}) =>
      QuestionFilter(
        tags: _tagFilter,
        types: _typeFilter,
        sourceNickname: _sourceFilter,
        folderIds:
            _currentFolderId != null ? [_currentFolderId!] : const [],
        wrongFirst: wrongFirst,
        keyword: _keyword,
        limit: limit,
      );

  Future<Question> save(Question q) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final toSave = q.id.isEmpty
        ? q.copyWith(
            id: CryptoService.generateId(),
            createdAt: now,
            updatedAt: now)
        : q.copyWith(updatedAt: now);
    await _db.upsertQuestion(toSave);
    await load();
    return toSave;
  }

  Future<void> delete(List<String> ids) async {
    await _db.deleteQuestions(ids);
    await load();
  }

  /// 批量追加标签（并集，去重）
  Future<void> setTagsFor(List<String> ids, List<String> tags) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final q in _all.where((e) => ids.contains(e.id))) {
      await _db.upsertQuestion(q.copyWith(
        tags: {...q.tags, ...tags}.toList(),
        updatedAt: now,
      ));
    }
    await load();
  }

  /// 批量设置难度（覆盖）
  Future<void> setDifficultyFor(List<String> ids, int level) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final q in _all.where((e) => ids.contains(e.id))) {
      await _db.upsertQuestion(q.copyWith(
        difficulty: level,
        updatedAt: now,
      ));
    }
    await load();
  }

  Future<List<Question>> importFromFile(String path,
      {Map<String, String>? mapping,
      String? htmlSelector,
      List<String> extraTags = const []}) async {
    final list = await _import.importFile(path,
        mapping: mapping, htmlSelector: htmlSelector);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final q in list) {
      final withTags = extraTags.isEmpty
          ? q
          : q.copyWith(tags: {...q.tags, ...extraTags}.toList());
      await _db.upsertQuestion(withTags.copyWith(updatedAt: now));
    }
    await load();
    return list;
  }

  /// 由筛选条件抽题（随机/顺序）。wrongFirst 时错题优先（按错次降序）。
  Future<List<Question>> pickQuestions(
      {required QuestionFilter filter, bool random = true, int? count}) async {
    var list = await _db.queryQuestions(
      tags: filter.tags,
      types: filter.types,
      sourceAuthorId: null,
      keyword: filter.keyword,
      folderIds: filter.folderIds,
    );
    if (filter.sourceNickname != null && filter.sourceNickname!.isNotEmpty) {
      list = list
          .where((q) => q.sourceNickname == filter.sourceNickname)
          .toList();
    }
    if (filter.wrongFirst) {
      final wrongs = await _db.allWrong();
      final wcount = {for (final w in wrongs) w.questionId: w.wrongCount};
      final wset = wcount.keys.toSet();
      list.sort((a, b) {
        final aw = wset.contains(a.id);
        final bw = wset.contains(b.id);
        if (aw != bw) return aw ? -1 : 1; // 错题优先
        if (aw) return wcount[b.id]!.compareTo(wcount[a.id]!); // 错次多优先
        return b.createdAt.compareTo(a.createdAt); // 非错题按创建序兜底
      });
    } else if (random) {
      list.shuffle();
    }
    final n = count ?? filter.limit ?? list.length;
    return list.take(n).toList();
  }

  Future<List<Question>> wrongQuestions() async {
    final wrongs = await _db.allWrong();
    final qids = wrongs.map((w) => w.questionId).toSet();
    final all = await _db.allQuestions();
    return all.where((q) => qids.contains(q.id)).toList();
  }

  /// 按题型配额抽题：对每种题型从符合筛选的题目中各取指定数量，合并返回。
  Future<List<Question>> pickByQuotas({
    required QuestionFilter filter,
    required Map<QuestionType, int> quotas,
    bool random = true,
  }) async {
    var pool = await _db.queryQuestions(
      tags: filter.tags,
      types: const [],
      sourceAuthorId: null,
      keyword: filter.keyword,
      folderIds: filter.folderIds,
    );
    if (filter.sourceNickname != null && filter.sourceNickname!.isNotEmpty) {
      pool = pool.where((q) => q.sourceNickname == filter.sourceNickname).toList();
    }
    final out = <Question>[];
    for (final entry in quotas.entries) {
      if (entry.value <= 0) continue;
      var ofType = pool.where((q) => q.type == entry.key).toList();
      if (random) ofType.shuffle();
      out.addAll(ofType.take(entry.value));
    }
    return out;
  }

  // ============ 题库夹（多层嵌套） ============
  void enterFolder(String? folderId) {
    _currentFolderId = folderId;
    _applyFilter();
    notifyListeners();
  }

  /// 当前夹的祖先链（根 → … → folderId），面包屑用
  List<QuestionFolder> folderChain(String? folderId) {
    final chain = <QuestionFolder>[];
    var cur = folderId;
    var guard = 0;
    while (cur != null && guard < 100) {
      QuestionFolder? f;
      for (final x in _folders) {
        if (x.id == cur) {
          f = x;
          break;
        }
      }
      if (f == null) break;
      chain.insert(0, f);
      cur = f.parentId;
      guard++;
    }
    return chain;
  }

  /// 某夹的直接子夹（parentId=null → 根级夹）
  List<QuestionFolder> childFolders(String? parentId) {
    return _folders.where((f) {
      final fp = f.parentId;
      return parentId == null ? fp == null : fp == parentId;
    }).toList();
  }

  /// 某夹直接题目数（UI 角标用）
  int questionCountIn(String? folderId) =>
      _all.where((q) => q.folderId == folderId).length;

  Future<QuestionFolder> createFolder({
    required String name,
    String? parentId,
  }) async {
    final f = QuestionFolder(
      id: CryptoService.generateId(),
      name: name.isEmpty ? '新文件夹' : name,
      parentId: parentId,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.saveFolder(f);
    await load();
    return f;
  }

  Future<void> renameFolder(String id, String name) async {
    QuestionFolder? existing;
    for (final f in _folders) {
      if (f.id == id) {
        existing = f;
        break;
      }
    }
    if (existing == null) return;
    await _db.saveFolder(QuestionFolder(
      id: existing.id,
      name: name.isEmpty ? existing.name : name,
      parentId: existing.parentId,
      createdAt: existing.createdAt,
      sortOrder: existing.sortOrder,
    ));
    await load();
  }

  Future<void> deleteFolder(String id) async {
    await _db.deleteFolder(id);
    if (_currentFolderId == id) _currentFolderId = null;
    await load();
  }

  Future<void> moveQuestionsToFolder(List<String> ids, String? folderId) async {
    await _db.moveQuestionsToFolder(ids, folderId);
    await load();
  }
}
