import 'dart:convert';

import '../constants.dart';

// ===================== 练习 =====================

/// 题目筛选条件（练习与考试共用）
class QuestionFilter {
  final List<String> tags; // 任一匹配
  final List<QuestionType> types;
  final String? sourceNickname; // 来源筛选
  final List<String> folderIds; // 题库夹筛选（多选）
  final bool wrongFirst; // 错题优先
  final String keyword;
  final int? limit;

  const QuestionFilter({
    this.tags = const [],
    this.types = const [],
    this.sourceNickname,
    this.folderIds = const [],
    this.wrongFirst = false,
    this.keyword = '',
    this.limit,
  });

  bool get isEmpty =>
      tags.isEmpty &&
      types.isEmpty &&
      (sourceNickname == null || sourceNickname!.isEmpty) &&
      folderIds.isEmpty &&
      !wrongFirst &&
      keyword.isEmpty;

  Map<String, dynamic> toJson() => {
        'tags': tags,
        'types': types.map((t) => t.name).toList(),
        'source_nickname': sourceNickname,
        'folder_ids': folderIds,
        'wrong_first': wrongFirst,
        'keyword': keyword,
        'limit': limit,
      };

  factory QuestionFilter.fromJson(Map<String, dynamic> j) => QuestionFilter(
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        types: (j['types'] as List?)
                ?.map((e) => QuestionType.fromString(e.toString()))
                .toList() ??
            const [],
        sourceNickname: j['source_nickname'] as String?,
        folderIds: (j['folder_ids'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        wrongFirst: j['wrong_first'] as bool? ?? false,
        keyword: (j['keyword'] as String?) ?? '',
        limit: j['limit'] as int?,
      );
}

/// 题库夹（支持多层嵌套：parentId 自引用，null/空 = 根级）
class QuestionFolder {
  final String id;
  final String name;
  final String? parentId;
  final int createdAt;
  final int sortOrder;

  const QuestionFolder({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toRow() => {
        'id': id,
        'name': name,
        'parent_id': parentId ?? '',
        'created_at': createdAt,
        'sort_order': sortOrder,
      };

  factory QuestionFolder.fromRow(Map<String, dynamic> r) => QuestionFolder(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        parentId: _nbe(r['parent_id']),
        createdAt: (r['created_at'] as int?) ?? 0,
        sortOrder: (r['sort_order'] as int?) ?? 0,
      );
}

/// 单题作答记录
class AnswerRecord {
  final String questionId;
  final String userAnswer;
  final bool correct;
  final int usedSeconds;
  final int? score; // 主观题人工评分（null = 未评/客观题）
  final bool graded; // true = 已判分（客观自动 / 主观人工）

  const AnswerRecord({
    required this.questionId,
    required this.userAnswer,
    required this.correct,
    required this.usedSeconds,
    this.score,
    this.graded = true,
  });

  AnswerRecord copyWith({
    String? questionId,
    String? userAnswer,
    bool? correct,
    int? usedSeconds,
    int? score,
    bool? graded,
  }) =>
      AnswerRecord(
        questionId: questionId ?? this.questionId,
        userAnswer: userAnswer ?? this.userAnswer,
        correct: correct ?? this.correct,
        usedSeconds: usedSeconds ?? this.usedSeconds,
        score: score ?? this.score,
        graded: graded ?? this.graded,
      );

  Map<String, dynamic> toJson() => {
        'question_id': questionId,
        'user_answer': userAnswer,
        'correct': correct,
        'used_seconds': usedSeconds,
        if (score != null) 'score': score,
        'graded': graded,
      };

  factory AnswerRecord.fromJson(Map<String, dynamic> j) => AnswerRecord(
        questionId: j['question_id'] as String,
        userAnswer: (j['user_answer'] as String?) ?? '',
        correct: j['correct'] as bool? ?? false,
        usedSeconds: (j['used_seconds'] as num?)?.toInt() ?? 0,
        score: (j['score'] as num?)?.toInt(),
        graded: j['graded'] as bool? ?? true,
      );
}

/// 练习会话
class PracticeSession {
  final String id;
  final QuestionFilter filter;
  final List<String> questionIds;
  final List<AnswerRecord> answers;
  final int currentIndex;
  final int startedAt;
  final int? finishedAt;
  final String status; // ongoing / finished
  final String mode; // 'instant' 边练边判 / 'batch' 集中判题

  const PracticeSession({
    required this.id,
    required this.filter,
    required this.questionIds,
    this.answers = const [],
    this.currentIndex = 0,
    required this.startedAt,
    this.finishedAt,
    this.status = 'ongoing',
    this.mode = 'instant',
  });

  PracticeSession copyWith({
    String? id,
    List<String>? questionIds,
    List<AnswerRecord>? answers,
    int? currentIndex,
    int? finishedAt,
    String? status,
    String? mode,
  }) =>
      PracticeSession(
        id: id ?? this.id,
        filter: filter,
        questionIds: questionIds ?? this.questionIds,
        answers: answers ?? this.answers,
        currentIndex: currentIndex ?? this.currentIndex,
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        status: status ?? this.status,
        mode: mode ?? this.mode,
      );

  Map<String, dynamic> toRow() => {
        'id': id,
        'filter_json': jsonEncode(filter.toJson()),
        'question_ids': jsonEncode(questionIds),
        'answers_json': jsonEncode(answers.map((a) => a.toJson()).toList()),
        'current_index': currentIndex,
        'started_at': startedAt,
        'finished_at': finishedAt ?? 0,
        'status': status,
        'mode': mode,
      };

  factory PracticeSession.fromRow(Map<String, dynamic> r) {
    List<dynamic> qids = jsonDecode((r['question_ids'] as String?) ?? '[]');
    List<dynamic> ansRaw = jsonDecode((r['answers_json'] as String?) ?? '[]');
    return PracticeSession(
      id: r['id'] as String,
      filter: QuestionFilter.fromJson(
          jsonDecode((r['filter_json'] as String?) ?? '{}')),
      questionIds: qids.map((e) => e.toString()).toList(),
      answers: ansRaw
          .map((e) => AnswerRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentIndex: (r['current_index'] as int?) ?? 0,
      startedAt: (r['started_at'] as int?) ?? 0,
      finishedAt: (r['finished_at'] as int?) == 0
          ? null
          : r['finished_at'] as int?,
      status: (r['status'] as String?) ?? 'ongoing',
      mode: (r['mode'] as String?) ?? 'instant',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'filter': filter.toJson(),
        'question_ids': questionIds,
        'answers': answers.map((a) => a.toJson()).toList(),
        'current_index': currentIndex,
        'started_at': startedAt,
        'finished_at': finishedAt,
        'status': status,
        'mode': mode,
      };

  factory PracticeSession.fromJson(Map<String, dynamic> j) => PracticeSession(
        id: (j['id'] as String?) ?? '',
        filter: QuestionFilter.fromJson(
            (j['filter'] as Map<String, dynamic>?) ?? const {}),
        questionIds: (j['question_ids'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        answers: (j['answers'] as List?)
                ?.map((e) => AnswerRecord.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        currentIndex: (j['current_index'] as num?)?.toInt() ?? 0,
        startedAt: (j['started_at'] as num?)?.toInt() ?? 0,
        finishedAt: (j['finished_at'] as num?)?.toInt(),
        status: (j['status'] as String?) ?? 'ongoing',
        mode: (j['mode'] as String?) ?? 'instant',
      );
}

// ===================== 考试 =====================

class ExamRule {
  final String id;
  final String name;
  final QuestionFilter filter;
  final int count;
  final int durationMinutes;
  final int scorePerQuestion;
  final bool allowReviewBack; // 是否允许回看
  final List<String>? questionIds; // 固定题目（null = 沿用 filter 抽题）
  final bool antiCheat; // 是否开启防作弊（独占全屏 + 禁快捷键 + 失焦惩罚）
  final Map<QuestionType, int>? typeQuotas; // 按题型配额抽题（null = 用 count 总数抽题）
  final double passRate; // 及格比例 0..1（默认 0.6）
  final int createdAt;

  const ExamRule({
    required this.id,
    required this.name,
    required this.filter,
    required this.count,
    required this.durationMinutes,
    this.scorePerQuestion = 5,
    this.allowReviewBack = true,
    this.questionIds,
    this.antiCheat = false,
    this.typeQuotas,
    this.passRate = 0.6,
    required this.createdAt,
  });

  /// 是否自定义选题（固定题目列表）
  bool get isPinned => questionIds != null && questionIds!.isNotEmpty;

  /// 是否按题型配额抽题
  bool get hasTypeQuotas =>
      typeQuotas != null && typeQuotas!.values.fold(0, (a, b) => a + b) > 0;

  /// 实际题目数（配额优先，否则 count）
  int get effectiveCount => hasTypeQuotas
      ? typeQuotas!.values.fold(0, (a, b) => a + b)
      : count;

  int get totalScore => effectiveCount * scorePerQuestion;

  Map<String, dynamic> toRow() => {
        'id': id,
        'name': name,
        'filter_json': jsonEncode(filter.toJson()),
        'count': count,
        'duration_minutes': durationMinutes,
        'score_per_question': scorePerQuestion,
        'allow_review_back': allowReviewBack ? 1 : 0,
        if (questionIds != null)
          'question_ids_json': jsonEncode(questionIds),
        'anti_cheat': antiCheat ? 1 : 0,
        'type_quotas_json': hasTypeQuotas
            ? jsonEncode({
                for (final e in typeQuotas!.entries) e.key.name: e.value
              })
            : '',
        'pass_rate': passRate,
        'created_at': createdAt,
      };

  factory ExamRule.fromRow(Map<String, dynamic> r) {
    final qidsRaw = r['question_ids_json'] as String?;
    final quotasRaw = r['type_quotas_json'] as String?;
    Map<QuestionType, int>? quotas;
    if (quotasRaw != null && quotasRaw.isNotEmpty) {
      try {
        final m = jsonDecode(quotasRaw) as Map<String, dynamic>;
        quotas = {
          for (final e in m.entries)
            QuestionType.fromString(e.key): (e.value as num).toInt()
        };
      } catch (_) {
        quotas = null;
      }
    }
    return ExamRule(
      id: r['id'] as String,
      name: (r['name'] as String?) ?? '',
      filter: QuestionFilter.fromJson(
          jsonDecode((r['filter_json'] as String?) ?? '{}')),
      count: (r['count'] as int?) ?? 0,
      durationMinutes: (r['duration_minutes'] as int?) ?? 0,
      scorePerQuestion: (r['score_per_question'] as int?) ?? 5,
      allowReviewBack: ((r['allow_review_back'] as int?) ?? 1) == 1,
      questionIds: qidsRaw == null
          ? null
          : (jsonDecode(qidsRaw) as List).map((e) => e.toString()).toList(),
      antiCheat: ((r['anti_cheat'] as int?) ?? 0) == 1,
      typeQuotas: quotas,
      passRate: (r['pass_rate'] as num?)?.toDouble() ?? 0.6,
      createdAt: (r['created_at'] as int?) ?? 0,
    );
  }
}

/// 考试结果（成绩单）
class ExamResult {
  final String id;
  final String ruleId;
  final String ruleName;
  final List<String> questionIds;
  final List<AnswerRecord> answers;
  final int startedAt;
  final int submittedAt;
  final int score;
  final int totalScore;
  final int correctCount;
  final int wrongCount;
  final int focusLostCount; // 失焦/切换次数
  final bool timeAnomaly; // 系统时间异常
  final bool autoSubmitted; // 离场超时自动交卷
  final int objectiveScore; // 客观题得分（系统自动判分）
  final int subjectiveScore; // 主观题得分（人工评卷，初始 0）
  final int subjectiveTotal; // 主观题满分（主观题数 × 每题分值）
  final bool graded; // true = 全部判分完成（无待评主观题）
  final bool passed; // 是否达到及格线

  const ExamResult({
    required this.id,
    required this.ruleId,
    required this.ruleName,
    required this.questionIds,
    required this.answers,
    required this.startedAt,
    required this.submittedAt,
    required this.score,
    required this.totalScore,
    required this.correctCount,
    required this.wrongCount,
    this.focusLostCount = 0,
    this.timeAnomaly = false,
    this.autoSubmitted = false,
    this.objectiveScore = 0,
    this.subjectiveScore = 0,
    this.subjectiveTotal = 0,
    this.graded = true,
    this.passed = false,
  });

  Map<String, dynamic> toRow() => {
        'id': id,
        'rule_id': ruleId,
        'rule_name': ruleName,
        'question_ids': jsonEncode(questionIds),
        'answers_json': jsonEncode(answers.map((a) => a.toJson()).toList()),
        'started_at': startedAt,
        'submitted_at': submittedAt,
        'score': score,
        'total_score': totalScore,
        'correct_count': correctCount,
        'wrong_count': wrongCount,
        'focus_lost_count': focusLostCount,
        'time_anomaly': timeAnomaly ? 1 : 0,
        'auto_submitted': autoSubmitted ? 1 : 0,
        'objective_score': objectiveScore,
        'subjective_score': subjectiveScore,
        'subjective_total': subjectiveTotal,
        'graded': graded ? 1 : 0,
        'passed': passed ? 1 : 0,
      };

  factory ExamResult.fromRow(Map<String, dynamic> r) {
    List<dynamic> qids = jsonDecode((r['question_ids'] as String?) ?? '[]');
    List<dynamic> ansRaw = jsonDecode((r['answers_json'] as String?) ?? '[]');
    return ExamResult(
      id: r['id'] as String,
      ruleId: (r['rule_id'] as String?) ?? '',
      ruleName: (r['rule_name'] as String?) ?? '',
      questionIds: qids.map((e) => e.toString()).toList(),
      answers: ansRaw
          .map((e) => AnswerRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      startedAt: (r['started_at'] as int?) ?? 0,
      submittedAt: (r['submitted_at'] as int?) ?? 0,
      score: (r['score'] as int?) ?? 0,
      totalScore: (r['total_score'] as int?) ?? 0,
      correctCount: (r['correct_count'] as int?) ?? 0,
      wrongCount: (r['wrong_count'] as int?) ?? 0,
      focusLostCount: (r['focus_lost_count'] as int?) ?? 0,
      timeAnomaly: ((r['time_anomaly'] as int?) ?? 0) == 1,
      autoSubmitted: ((r['auto_submitted'] as int?) ?? 0) == 1,
      objectiveScore: (r['objective_score'] as int?) ?? 0,
      subjectiveScore: (r['subjective_score'] as int?) ?? 0,
      subjectiveTotal: (r['subjective_total'] as int?) ?? 0,
      graded: ((r['graded'] as int?) ?? 1) == 1,
      passed: ((r['passed'] as int?) ?? 0) == 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'rule_id': ruleId,
        'rule_name': ruleName,
        'question_ids': questionIds,
        'answers': answers.map((a) => a.toJson()).toList(),
        'started_at': startedAt,
        'submitted_at': submittedAt,
        'score': score,
        'total_score': totalScore,
        'correct_count': correctCount,
        'wrong_count': wrongCount,
        'focus_lost_count': focusLostCount,
        'time_anomaly': timeAnomaly,
        'auto_submitted': autoSubmitted,
        'objective_score': objectiveScore,
        'subjective_score': subjectiveScore,
        'subjective_total': subjectiveTotal,
        'graded': graded,
        'passed': passed,
      };

  factory ExamResult.fromJson(Map<String, dynamic> j) => ExamResult(
        id: (j['id'] as String?) ?? '',
        ruleId: (j['rule_id'] as String?) ?? '',
        ruleName: (j['rule_name'] as String?) ?? '',
        questionIds: (j['question_ids'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        answers: (j['answers'] as List?)
                ?.map((e) => AnswerRecord.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        startedAt: (j['started_at'] as num?)?.toInt() ?? 0,
        submittedAt: (j['submitted_at'] as num?)?.toInt() ?? 0,
        score: (j['score'] as num?)?.toInt() ?? 0,
        totalScore: (j['total_score'] as num?)?.toInt() ?? 0,
        correctCount: (j['correct_count'] as num?)?.toInt() ?? 0,
        wrongCount: (j['wrong_count'] as num?)?.toInt() ?? 0,
        focusLostCount: (j['focus_lost_count'] as num?)?.toInt() ?? 0,
        timeAnomaly: j['time_anomaly'] as bool? ?? false,
        autoSubmitted: j['auto_submitted'] as bool? ?? false,
        objectiveScore: (j['objective_score'] as num?)?.toInt() ?? 0,
        subjectiveScore: (j['subjective_score'] as num?)?.toInt() ?? 0,
        subjectiveTotal: (j['subjective_total'] as num?)?.toInt() ?? 0,
        graded: j['graded'] as bool? ?? true,
        passed: j['passed'] as bool? ?? false,
      );
}

// ===================== 错题本 =====================

class WrongQuestion {
  final String id;
  final String questionId;
  final int wrongCount;
  final int lastWrongAt;
  final int firstWrongAt;
  final int mastery; // 0 未掌握 / 1 复习中 / 2 已掌握
  final int? lastPracticedAt; // 最近一次答对练习时间
  final String? customGroup; // 自定义分组名
  final int consecutiveCorrect; // 连续答对次数（达阈值自动移出错题本）
  final String? sourceSessionId; // 最近一次答错的考试/练习场次 id
  final String? sourceSessionType; // 'practice' / 'exam' / 'quick'
  final String? sourceSessionName; // 规则名 / 筛选摘要 / '错题本快练'

  const WrongQuestion({
    required this.id,
    required this.questionId,
    required this.wrongCount,
    required this.lastWrongAt,
    required this.firstWrongAt,
    this.mastery = 0,
    this.lastPracticedAt,
    this.customGroup,
    this.consecutiveCorrect = 0,
    this.sourceSessionId,
    this.sourceSessionType,
    this.sourceSessionName,
  });

  Map<String, dynamic> toRow() => {
        'id': id,
        'question_id': questionId,
        'wrong_count': wrongCount,
        'last_wrong_at': lastWrongAt,
        'first_wrong_at': firstWrongAt,
        'mastery': mastery,
        'last_practiced_at': lastPracticedAt,
        'custom_group': customGroup,
        'consecutive_correct': consecutiveCorrect,
        'source_session_id': sourceSessionId,
        'source_session_type': sourceSessionType,
        'source_session_name': sourceSessionName,
      };

  factory WrongQuestion.fromRow(Map<String, dynamic> r) => WrongQuestion(
        id: r['id'] as String,
        questionId: (r['question_id'] as String?) ?? '',
        wrongCount: (r['wrong_count'] as int?) ?? 0,
        lastWrongAt: (r['last_wrong_at'] as int?) ?? 0,
        firstWrongAt: (r['first_wrong_at'] as int?) ?? 0,
        mastery: (r['mastery'] as int?) ?? 0,
        lastPracticedAt: r['last_practiced_at'] as int?,
        customGroup: _nbe(r['custom_group']),
        consecutiveCorrect: (r['consecutive_correct'] as int?) ?? 0,
        sourceSessionId: _nbe(r['source_session_id']),
        sourceSessionType: _nbe(r['source_session_type']),
        sourceSessionName: _nbe(r['source_session_name']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'question_id': questionId,
        'wrong_count': wrongCount,
        'last_wrong_at': lastWrongAt,
        'first_wrong_at': firstWrongAt,
        'mastery': mastery,
        'last_practiced_at': lastPracticedAt,
        'custom_group': customGroup,
        'consecutive_correct': consecutiveCorrect,
        'source_session_id': sourceSessionId,
        'source_session_type': sourceSessionType,
        'source_session_name': sourceSessionName,
      };

  factory WrongQuestion.fromJson(Map<String, dynamic> j) => WrongQuestion(
        id: (j['id'] as String?) ?? '',
        questionId: (j['question_id'] as String?) ?? '',
        wrongCount: (j['wrong_count'] as num?)?.toInt() ?? 0,
        lastWrongAt: (j['last_wrong_at'] as num?)?.toInt() ?? 0,
        firstWrongAt: (j['first_wrong_at'] as num?)?.toInt() ?? 0,
        mastery: (j['mastery'] as num?)?.toInt() ?? 0,
        lastPracticedAt: (j['last_practiced_at'] as num?)?.toInt(),
        customGroup: j['custom_group'] as String?,
        consecutiveCorrect:
            (j['consecutive_correct'] as num?)?.toInt() ?? 0,
        sourceSessionId: j['source_session_id'] as String?,
        sourceSessionType: j['source_session_type'] as String?,
        sourceSessionName: j['source_session_name'] as String?,
      );
}

/// 错题自定义分组（错题的 customGroup 存分组名，删除分组不影响已归类错题）
class WrongGroup {
  final String id;
  final String name;
  final int createdAt;

  const WrongGroup({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toRow() =>
      {'id': id, 'name': name, 'created_at': createdAt};

  factory WrongGroup.fromRow(Map<String, dynamic> r) => WrongGroup(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        createdAt: (r['created_at'] as int?) ?? 0,
      );
}

// ===================== AI =====================

/// AI 对话附件元信息（图片走多模态识图，纯文本类拼入提问上下文）
class AttachmentMeta {
  final String id;
  final String fileName;
  final String mimeType;
  final String storedPath; // materials/attachments/<id>.<ext>
  final bool isImage; // mimeType 以 image/ 开头
  final int sizeBytes;

  const AttachmentMeta({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.storedPath,
    required this.isImage,
    required this.sizeBytes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'file_name': fileName,
        'mime_type': mimeType,
        'stored_path': storedPath,
        'is_image': isImage,
        'size_bytes': sizeBytes,
      };

  factory AttachmentMeta.fromJson(Map<String, dynamic> j) => AttachmentMeta(
        id: (j['id'] as String?) ?? '',
        fileName: (j['file_name'] as String?) ?? '',
        mimeType: (j['mime_type'] as String?) ?? '',
        storedPath: (j['stored_path'] as String?) ?? '',
        isImage: j['is_image'] as bool? ?? false,
        sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
      );
}

enum AIServiceType { openai, ollama }

extension AIServiceTypeX on AIServiceType {
  String get name => this == AIServiceType.openai ? 'openai' : 'ollama';
  static AIServiceType fromName(String? s) =>
      s == 'ollama' ? AIServiceType.ollama : AIServiceType.openai;
}

class AIServiceConfig {
  final String id;
  final String name;
  final AIServiceType type;
  final String baseUrl; // 如 https://api.openai.com/v1 或 http://localhost:11434
  final String model;
  final String apiKeyEncrypted; // AES-GCM 密文（密钥派生自主密码）
  final bool hasApiKey;

  const AIServiceConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.baseUrl,
    required this.model,
    this.apiKeyEncrypted = '',
    this.hasApiKey = false,
  });

  Map<String, dynamic> toRow() => {
        'id': id,
        'name': name,
        'type': type.name,
        'base_url': baseUrl,
        'model': model,
        'api_key_encrypted': apiKeyEncrypted,
        'has_api_key': hasApiKey ? 1 : 0,
      };

  factory AIServiceConfig.fromRow(Map<String, dynamic> r) => AIServiceConfig(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        type: AIServiceTypeX.fromName(r['type'] as String?),
        baseUrl: (r['base_url'] as String?) ?? '',
        model: (r['model'] as String?) ?? '',
        apiKeyEncrypted: (r['api_key_encrypted'] as String?) ?? '',
        hasApiKey: ((r['has_api_key'] as int?) ?? 0) == 1,
      );
}

/// AI 智能体（人格配置）：引用一个 AIServiceConfig，附加系统提示词/模型覆盖/模型参数
class AIAgent {
  final String id;
  final String name;
  final String? avatarPath;
  final String systemPrompt;
  final String serviceId; // → AIServiceConfig.id
  final String? model; // null = 用 service.model
  final double? temperature; // null = 服务端默认
  final double? topP;
  final int? maxTokens;
  final int createdAt;

  const AIAgent({
    required this.id,
    required this.name,
    this.avatarPath,
    required this.systemPrompt,
    required this.serviceId,
    this.model,
    this.temperature,
    this.topP,
    this.maxTokens,
    required this.createdAt,
  });

  Map<String, dynamic> toRow() => {
        'id': id,
        'name': name,
        'avatar_path': avatarPath ?? '',
        'system_prompt': systemPrompt,
        'service_id': serviceId,
        'model': model ?? '',
        'temperature': temperature,
        'top_p': topP,
        'max_tokens': maxTokens,
        'created_at': createdAt,
      };

  factory AIAgent.fromRow(Map<String, dynamic> r) {
    final m = (r['model'] as String?) ?? '';
    return AIAgent(
      id: r['id'] as String,
      name: (r['name'] as String?) ?? '',
      avatarPath: _nbe(r['avatar_path']),
      systemPrompt: (r['system_prompt'] as String?) ?? '',
      serviceId: (r['service_id'] as String?) ?? '',
      model: m.isEmpty ? null : m,
      temperature: (r['temperature'] as num?)?.toDouble(),
      topP: (r['top_p'] as num?)?.toDouble(),
      maxTokens: r['max_tokens'] as int?,
      createdAt: (r['created_at'] as int?) ?? 0,
    );
  }
}

class AIConversation {
  final String id;
  final String title;
  final String serviceId;
  final String? agentId; // 关联智能体；旧会话为 null
  final int createdAt;
  final int updatedAt;

  const AIConversation({
    required this.id,
    required this.title,
    required this.serviceId,
    this.agentId,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toRow() => {
        'id': id,
        'title': title,
        'service_id': serviceId,
        'agent_id': agentId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory AIConversation.fromRow(Map<String, dynamic> r) => AIConversation(
        id: r['id'] as String,
        title: (r['title'] as String?) ?? '',
        serviceId: (r['service_id'] as String?) ?? '',
        agentId: _nbe(r['agent_id']),
        createdAt: (r['created_at'] as int?) ?? 0,
        updatedAt: (r['updated_at'] as int?) ?? 0,
      );
}

class AIMessage {
  final String id;
  final String conversationId;
  final String role; // user / assistant / system
  final String content;
  final List<AttachmentMeta> attachments; // 图片附件元信息（纯文本类已拼入 content）
  final int createdAt;

  const AIMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.attachments = const [],
    required this.createdAt,
  });

  Map<String, dynamic> toRow() => {
        'id': id,
        'conversation_id': conversationId,
        'role': role,
        'content': content,
        'attachments_json': attachments.isEmpty
            ? ''
            : jsonEncode(attachments.map((a) => a.toJson()).toList()),
        'created_at': createdAt,
      };

  factory AIMessage.fromRow(Map<String, dynamic> r) {
    final raw = (r['attachments_json'] as String?) ?? '';
    List<AttachmentMeta> atts = const [];
    if (raw.isNotEmpty) {
      try {
        atts = (jsonDecode(raw) as List)
            .map((e) => AttachmentMeta.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        atts = const [];
      }
    }
    return AIMessage(
      id: r['id'] as String,
      conversationId: (r['conversation_id'] as String?) ?? '',
      role: (r['role'] as String?) ?? 'user',
      content: (r['content'] as String?) ?? '',
      attachments: atts,
      createdAt: (r['created_at'] as int?) ?? 0,
    );
  }
}

// ===================== 阅读器 =====================

enum MaterialFormat { pdf, docx, pptx, xlsx, html, txt, md, csv, epub, odt, odp, ods, rtf, unknown }

extension MaterialFormatX on MaterialFormat {
  String get name {
    switch (this) {
      case MaterialFormat.pdf:
        return 'pdf';
      case MaterialFormat.docx:
        return 'docx';
      case MaterialFormat.pptx:
        return 'pptx';
      case MaterialFormat.xlsx:
        return 'xlsx';
      case MaterialFormat.html:
        return 'html';
      case MaterialFormat.txt:
        return 'txt';
      case MaterialFormat.md:
        return 'md';
      case MaterialFormat.csv:
        return 'csv';
      case MaterialFormat.epub:
        return 'epub';
      case MaterialFormat.odt:
        return 'odt';
      case MaterialFormat.odp:
        return 'odp';
      case MaterialFormat.ods:
        return 'ods';
      case MaterialFormat.rtf:
        return 'rtf';
      case MaterialFormat.unknown:
        return 'unknown';
    }
  }

  static MaterialFormat fromExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return MaterialFormat.pdf;
      case 'docx':
      case 'doc':
        return MaterialFormat.docx;
      case 'pptx':
      case 'ppt':
        return MaterialFormat.pptx;
      case 'xlsx':
      case 'xls':
        return MaterialFormat.xlsx;
      case 'html':
      case 'htm':
        return MaterialFormat.html;
      case 'md':
      case 'markdown':
        return MaterialFormat.md;
      case 'csv':
        return MaterialFormat.csv;
      case 'txt':
      case 'log':
        return MaterialFormat.txt;
      case 'epub':
        return MaterialFormat.epub;
      case 'odt':
        return MaterialFormat.odt;
      case 'odp':
        return MaterialFormat.odp;
      case 'ods':
        return MaterialFormat.ods;
      case 'rtf':
        return MaterialFormat.rtf;
      default:
        return MaterialFormat.unknown;
    }
  }
}

class ReadingMaterial {
  final String id;
  final String title;
  final MaterialFormat format;
  final String storedPath; // 应用私有目录中的副本路径
  final int sizeBytes;

  /// 来源
  final String? sourceNickname;
  final String? sourceAuthorId;

  final double progress; // 0..1
  final bool finished;
  final int addedAt;
  final int lastReadAt;

  const ReadingMaterial({
    required this.id,
    required this.title,
    required this.format,
    required this.storedPath,
    required this.sizeBytes,
    this.sourceNickname,
    this.sourceAuthorId,
    this.progress = 0,
    this.finished = false,
    required this.addedAt,
    required this.lastReadAt,
  });

  bool get isFromShare =>
      sourceAuthorId != null && sourceAuthorId!.isNotEmpty;

  Map<String, dynamic> toRow() => {
        'id': id,
        'title': title,
        'format': format.name,
        'stored_path': storedPath,
        'size_bytes': sizeBytes,
        'source_nickname': sourceNickname ?? '',
        'source_author_id': sourceAuthorId ?? '',
        'progress': progress,
        'finished': finished ? 1 : 0,
        'added_at': addedAt,
        'last_read_at': lastReadAt,
      };

  factory ReadingMaterial.fromRow(Map<String, dynamic> r) => ReadingMaterial(
        id: r['id'] as String,
        title: (r['title'] as String?) ?? '',
        format: _fmtFromName(r['format'] as String?),
        storedPath: (r['stored_path'] as String?) ?? '',
        sizeBytes: (r['size_bytes'] as int?) ?? 0,
        sourceNickname: _nbe(r['source_nickname']),
        sourceAuthorId: _nbe(r['source_author_id']),
        progress: (r['progress'] as num?)?.toDouble() ?? 0,
        finished: ((r['finished'] as int?) ?? 0) == 1,
        addedAt: (r['added_at'] as int?) ?? 0,
        lastReadAt: (r['last_read_at'] as int?) ?? 0,
      );
}

MaterialFormat _fmtFromName(String? s) {
  switch (s) {
    case 'pdf':
      return MaterialFormat.pdf;
    case 'docx':
      return MaterialFormat.docx;
    case 'pptx':
      return MaterialFormat.pptx;
    case 'xlsx':
      return MaterialFormat.xlsx;
    case 'html':
      return MaterialFormat.html;
    case 'md':
      return MaterialFormat.md;
    case 'csv':
      return MaterialFormat.csv;
    case 'epub':
      return MaterialFormat.epub;
    case 'odt':
      return MaterialFormat.odt;
    case 'odp':
      return MaterialFormat.odp;
    case 'ods':
      return MaterialFormat.ods;
    case 'rtf':
      return MaterialFormat.rtf;
    default:
      return MaterialFormat.txt;
  }
}

// ===================== 笔记 / 批注 =====================

enum NoteType { highlight, underline, drawing, sticky, bookmark }

extension NoteTypeX on NoteType {
  String get name {
    switch (this) {
      case NoteType.highlight:
        return 'highlight';
      case NoteType.underline:
        return 'underline';
      case NoteType.drawing:
        return 'drawing';
      case NoteType.sticky:
        return 'sticky';
      case NoteType.bookmark:
        return 'bookmark';
    }
  }

  static NoteType fromName(String? s) {
    switch (s) {
      case 'underline':
        return NoteType.underline;
      case 'drawing':
        return NoteType.drawing;
      case 'sticky':
        return NoteType.sticky;
      case 'bookmark':
        return NoteType.bookmark;
      default:
        return NoteType.highlight;
    }
  }
}

class Note {
  final String id;
  final String materialId;
  final NoteType type;
  final int pageIndex;
  final String payload; // JSON：高亮偏移 / 绘图点序列 / 便签位置
  final String text;
  final bool isOriginal; // true=原始作者笔记，false=我的笔记
  final String? sourceNickname;
  final int createdAt;

  const Note({
    required this.id,
    required this.materialId,
    required this.type,
    required this.pageIndex,
    required this.payload,
    this.text = '',
    this.isOriginal = false,
    this.sourceNickname,
    required this.createdAt,
  });

  Map<String, dynamic> toRow() => {
        'id': id,
        'material_id': materialId,
        'type': type.name,
        'page_index': pageIndex,
        'payload': payload,
        'text': text,
        'is_original': isOriginal ? 1 : 0,
        'source_nickname': sourceNickname ?? '',
        'created_at': createdAt,
      };

  factory Note.fromRow(Map<String, dynamic> r) => Note(
        id: r['id'] as String,
        materialId: (r['material_id'] as String?) ?? '',
        type: NoteTypeX.fromName(r['type'] as String?),
        pageIndex: (r['page_index'] as int?) ?? 0,
        payload: (r['payload'] as String?) ?? '',
        text: (r['text'] as String?) ?? '',
        isOriginal: ((r['is_original'] as int?) ?? 0) == 1,
        sourceNickname: _nbe(r['source_nickname']),
        createdAt: (r['created_at'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'material_id': materialId,
        'type': type.name,
        'page_index': pageIndex,
        'payload': payload,
        'text': text,
        'is_original': isOriginal,
        'source_nickname': sourceNickname,
        'created_at': createdAt,
      };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        materialId: (j['material_id'] as String?) ?? '',
        type: NoteTypeX.fromName(j['type'] as String?),
        pageIndex: (j['page_index'] as num?)?.toInt() ?? 0,
        payload: (j['payload'] as String?) ?? '',
        text: (j['text'] as String?) ?? '',
        isOriginal: j['is_original'] as bool? ?? false,
        sourceNickname: j['source_nickname'] as String?,
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      );

  Note copyWith({
    String? id,
    String? materialId,
    NoteType? type,
    int? pageIndex,
    String? payload,
    String? text,
    bool? isOriginal,
    String? sourceNickname,
    int? createdAt,
  }) =>
      Note(
        id: id ?? this.id,
        materialId: materialId ?? this.materialId,
        type: type ?? this.type,
        pageIndex: pageIndex ?? this.pageIndex,
        payload: payload ?? this.payload,
        text: text ?? this.text,
        isOriginal: isOriginal ?? this.isOriginal,
        sourceNickname: sourceNickname ?? this.sourceNickname,
        createdAt: createdAt ?? this.createdAt,
      );
}

String? _nbe(Object? v) {
  final s = v?.toString();
  if (s == null || s.isEmpty) return null;
  return s;
}

// 引用以避免常量被 tree-shake 警告
// ignore: unused_element
const int _kFmtVersion = AppConstants.formatVersion;
