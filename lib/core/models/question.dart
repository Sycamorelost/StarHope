import 'dart:convert';

import '../constants.dart';

/// 题目数据模型 —— 核心层
///
/// 支持单选/多选/填空/判断/不定项。题干为 Markdown，可实时预览。
/// 每道题可携带来源（分享者信息），界面固定位置展示。
class Question {
  final String id;
  final QuestionType type;

  /// Markdown 题干
  final String stem;

  /// 选项列表（填空题为空）
  final List<String> options;

  /// 标准答案：
  /// - 单选/判断：选项索引字符串如 "0"
  /// - 多选/不定项：逗号分隔索引如 "0,2"
  /// - 填空：以 `||` 分隔多个空的标准答案
  final String answer;

  /// 解析（Markdown，可含分享者来源）
  final String explanation;

  /// 标签
  final List<String> tags;

  /// 难度 1-5
  final int difficulty;

  /// 来源分享者昵称（本库自建为空）
  final String? sourceNickname;
  final String? sourceAuthorId;
  final String? sourceSocial; // "github:xx;qq:yy;wechat:zz" 仅在公开时
  final String? sourceExportedAt;

  /// 所属题库夹（null = 根级/未归档）
  final String? folderId;

  final int createdAt;
  final int updatedAt;

  /// 使用统计（被练次数 / 答对次数 / 最近练习时间戳）
  final int practiceCount;
  final int correctCount;
  final int? lastPracticedAt;

  Question({
    required this.id,
    required this.type,
    required this.stem,
    this.options = const [],
    required this.answer,
    this.explanation = '',
    this.tags = const [],
    this.difficulty = 3,
    this.sourceNickname,
    this.sourceAuthorId,
    this.sourceSocial,
    this.sourceExportedAt,
    this.folderId,
    required this.createdAt,
    required this.updatedAt,
    this.practiceCount = 0,
    this.correctCount = 0,
    this.lastPracticedAt,
  });

  bool get isFromShare => sourceAuthorId != null && sourceAuthorId!.isNotEmpty;

  Map<String, dynamic> toRow() => {
        'id': id,
        'type': type.name,
        'stem': stem,
        'options': jsonEncode(options),
        'answer': answer,
        'explanation': explanation,
        'tags': tags.join(','),
        'difficulty': difficulty,
        'source_nickname': sourceNickname ?? '',
        'source_author_id': sourceAuthorId ?? '',
        'source_social': sourceSocial ?? '',
        'source_exported_at': sourceExportedAt ?? '',
        'folder_id': folderId,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'practice_count': practiceCount,
        'correct_count': correctCount,
        'last_practiced_at': lastPracticedAt,
      };

  factory Question.fromRow(Map<String, dynamic> r) => Question(
        id: r['id'] as String,
        type: QuestionType.fromString(r['type'] as String?),
        stem: (r['stem'] as String?) ?? '',
        options: _parseOptions(r['options']),
        answer: (r['answer'] as String?) ?? '',
        explanation: (r['explanation'] as String?) ?? '',
        tags: ((r['tags'] as String?) ?? '')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        difficulty: (r['difficulty'] as int?) ?? 3,
        sourceNickname: _nbe(r['source_nickname']),
        sourceAuthorId: _nbe(r['source_author_id']),
        sourceSocial: _nbe(r['source_social']),
        sourceExportedAt: _nbe(r['source_exported_at']),
        folderId: _nbe(r['folder_id']),
        createdAt: (r['created_at'] as int?) ?? 0,
        updatedAt: (r['updated_at'] as int?) ?? 0,
        practiceCount: (r['practice_count'] as int?) ?? 0,
        correctCount: (r['correct_count'] as int?) ?? 0,
        lastPracticedAt: r['last_practiced_at'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'stem': stem,
        'options': options,
        'answer': answer,
        'explanation': explanation,
        'tags': tags,
        'difficulty': difficulty,
        if (sourceNickname != null) 'source_nickname': sourceNickname,
        if (sourceAuthorId != null) 'source_author_id': sourceAuthorId,
        if (sourceSocial != null) 'source_social': sourceSocial,
        if (sourceExportedAt != null) 'source_exported_at': sourceExportedAt,
        if (folderId != null) 'folder_id': folderId,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'practice_count': practiceCount,
        'correct_count': correctCount,
        if (lastPracticedAt != null) 'last_practiced_at': lastPracticedAt,
      };

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        id: j['id'] as String,
        type: QuestionType.fromString(j['type'] as String?),
        stem: (j['stem'] as String?) ?? '',
        options:
            (j['options'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        answer: (j['answer'] as String?) ?? '',
        explanation: (j['explanation'] as String?) ?? '',
        tags: (j['tags'] as List?)
                ?.map((e) => e.toString().trim())
                .toList() ??
            const [],
        difficulty: (j['difficulty'] as num?)?.toInt() ?? 3,
        sourceNickname: j['source_nickname'] as String?,
        sourceAuthorId: j['source_author_id'] as String?,
        sourceSocial: j['source_social'] as String?,
        sourceExportedAt: j['source_exported_at'] as String?,
        folderId: j['folder_id'] as String?,
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
        practiceCount: (j['practice_count'] as num?)?.toInt() ?? 0,
        correctCount: (j['correct_count'] as num?)?.toInt() ?? 0,
        lastPracticedAt: (j['last_practiced_at'] as num?)?.toInt(),
      );

  Question copyWith({
    String? id,
    QuestionType? type,
    String? stem,
    List<String>? options,
    String? answer,
    String? explanation,
    List<String>? tags,
    int? difficulty,
    String? sourceNickname,
    String? sourceAuthorId,
    String? sourceSocial,
    String? sourceExportedAt,
    String? folderId,
    int? createdAt,
    int? updatedAt,
    int? practiceCount,
    int? correctCount,
    int? lastPracticedAt,
  }) =>
      Question(
        id: id ?? this.id,
        type: type ?? this.type,
        stem: stem ?? this.stem,
        options: options ?? this.options,
        answer: answer ?? this.answer,
        explanation: explanation ?? this.explanation,
        tags: tags ?? this.tags,
        difficulty: difficulty ?? this.difficulty,
        sourceNickname: sourceNickname ?? this.sourceNickname,
        sourceAuthorId: sourceAuthorId ?? this.sourceAuthorId,
        sourceSocial: sourceSocial ?? this.sourceSocial,
        sourceExportedAt: sourceExportedAt ?? this.sourceExportedAt,
        folderId: folderId ?? this.folderId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        practiceCount: practiceCount ?? this.practiceCount,
        correctCount: correctCount ?? this.correctCount,
        lastPracticedAt: lastPracticedAt ?? this.lastPracticedAt,
      );
}

List<String> _parseOptions(Object? v) {
  if (v == null) return const [];
  if (v is String) {
    if (v.isEmpty) return const [];
    try {
      final decoded = jsonDecode(v);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {
      // 兼容旧格式：按换行切分
      return v.split('\n').where((s) => s.isNotEmpty).toList();
    }
  }
  if (v is List) return v.map((e) => e.toString()).toList();
  return const [];
}

String? _nbe(Object? v) {
  final s = v?.toString();
  if (s == null || s.isEmpty) return null;
  return s;
}
