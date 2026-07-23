import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/constants.dart';
import '../core/crypto/crypto_service.dart';
import '../core/models/models.dart';
import '../core/models/question.dart';
import '../core/models/share_meta.dart';
import '../core/models/user.dart';
import '../core/starhope_format.dart';
import 'database/database.dart';
import 'data_modules.dart';
import 'file_storage_service.dart';
import 'question_serializer.dart';
import 'storage_config.dart';

/// 导出 / 导入 / 防伪服务（服务层）
class ExportService {
  final AppDatabase _db = AppDatabase.instance;

  /// 构造分享者元数据（导出时由用户选择是否公开社交账号）
  ShareMeta buildMeta(User author, ShareContentType type,
      {bool publicSocial = false, DateTime? now}) {
    final t = now ?? DateTime.now();
    return ShareMeta(
      authorId: author.id,
      nickname: author.nickname,
      github: publicSocial ? author.github : null,
      qq: publicSocial ? author.qq : null,
      wechat: publicSocial ? author.wechat : null,
      exportedAt: t.toUtc().toIso8601String(),
      contentType: type,
      publicSocial: publicSocial,
    );
  }

  // ============ 题库导出 ============
  Future<void> exportQuestions({
    required String path,
    required List<Question> questions,
    required ShareMeta meta,
  }) async {
    final payload = {
      'questions': questions.map((q) => q.toJson()).toList(),
    };
    await StarHopeFile.write(
      path: path,
      meta: meta,
      payload: payload,
    );
  }

  // ============ 错题导出（按筛选/分组导出错题子集 + 对应题目） ============
  Future<void> exportWrongQuestions({
    required String path,
    required List<WrongQuestion> wrongs,
    required List<Question> questions,
    required ShareMeta meta,
  }) async {
    final payload = {
      'wrong_questions': wrongs.map((w) => w.toJson()).toList(),
      'questions': questions.map((q) => q.toJson()).toList(),
    };
    await StarHopeFile.write(path: path, meta: meta, payload: payload);
  }

  // ============ 资料导出（含笔记与文件） ============
  Future<void> exportMaterial({
    required String path,
    required ReadingMaterial material,
    required List<Note> notes,
    required ShareMeta meta,
  }) async {
    final fileBytes = await File(material.storedPath).readAsBytes();
    final fileName = '${material.id}.${material.format.name}';
    final payload = {
      'material': _materialJson(material),
      'notes': notes.map((n) => n.toJson()).toList(),
    };
    await StarHopeFile.write(
      path: path,
      meta: meta,
      payload: payload,
      files: {fileName: Uint8List.fromList(fileBytes)},
    );
  }

  Map<String, dynamic> _materialJson(ReadingMaterial m) => {
        'id': m.id,
        'title': m.title,
        'format': m.format.name,
        'size_bytes': m.sizeBytes,
        'source_nickname': m.sourceNickname,
        'source_author_id': m.sourceAuthorId,
        'added_at': m.addedAt,
      };

  // ============ 全库备份 ============
  Future<void> fullBackup({
    required String path,
    required User author,
    required ShareMeta meta,
    Set<String>? modules,
  }) async {
    final m = modules ??
        const {
          'questions', 'folders', 'practices', 'exam_rules', 'exam_results',
          'wrong', 'wrong_groups', 'materials', 'ai_services', 'ai_agents',
          'ai_conversations', 'ai_messages', 'plugins'
        };
    bool on(String k) => m.contains(k);
    final files = <String, Uint8List>{};
    final payload = <String, dynamic>{};

    if (on('questions')) {
      payload['questions'] =
          (await _db.allQuestions()).map((q) => q.toJson()).toList();
    }
    if (on('folders')) {
      payload['question_folders'] =
          (await _db.allFolders()).map((f) => f.toRow()).toList();
    }
    if (on('practices')) {
      payload['practice_sessions'] =
          (await _db.allPractices()).map((p) => p.toRow()).toList();
    }
    if (on('exam_rules')) {
      payload['exam_rules'] =
          (await _db.allExamRules()).map((r) => r.toRow()).toList();
    }
    if (on('exam_results')) {
      payload['exam_results'] =
          (await _db.allExamResults()).map((r) => r.toRow()).toList();
    }
    if (on('wrong')) {
      payload['wrong_questions'] =
          (await _db.allWrong()).map((w) => w.toRow()).toList();
    }
    if (on('wrong_groups')) {
      payload['wrong_groups'] =
          (await _db.allWrongGroups()).map((g) => g.toRow()).toList();
    }
    if (on('materials')) {
      final materials = await _db.allMaterials();
      final materialJson = <Map<String, dynamic>>[];
      for (final mat in materials) {
        if (await File(mat.storedPath).exists()) {
          final bytes = await File(mat.storedPath).readAsBytes();
          files['${mat.id}.${mat.format.name}'] = Uint8List.fromList(bytes);
        }
        materialJson.add({
          ..._materialJson(mat),
          'progress': mat.progress,
          'finished': mat.finished,
          'last_read_at': mat.lastReadAt,
          'notes': (await _db.notesOf(mat.id)).map((n) => n.toJson()).toList(),
        });
      }
      payload['materials'] = materialJson;
    }
    if (on('ai_services')) {
      // 不导出 API 密钥（安全），仅服务连接信息
      payload['ai_services'] = (await _db.allAIServices())
          .map((s) => {
                'id': s.id,
                'name': s.name,
                'type': s.type.name,
                'base_url': s.baseUrl,
                'model': s.model,
                'has_api_key': false,
              })
          .toList();
    }
    if (on('ai_agents')) {
      payload['ai_agents'] =
          (await _db.allAgents()).map((a) => a.toRow()).toList();
    }
    if (on('ai_conversations')) {
      payload['ai_conversations'] =
          (await _db.allConversations()).map((c) => c.toRow()).toList();
    }
    if (on('ai_messages')) {
      final convs = await _db.allConversations();
      final allMsgs = <Map<String, dynamic>>[];
      for (final c in convs) {
        for (final msg in await _db.messagesOf(c.id)) {
          allMsgs.add(msg.toRow());
        }
      }
      payload['ai_messages'] = allMsgs;
    }
    if (on('plugins')) {
      // 插件 = DB 登记行 + 磁盘上的插件目录（manifest/main.js/icon/storage.json 等）
      payload['plugins'] = await _db.loadPlugins();
      final pluginsRoot =
          Directory(p.join(await StorageConfig.dataRoot(), 'plugins'));
      if (await pluginsRoot.exists()) {
        await for (final sub
            in pluginsRoot.list(recursive: false, followLinks: false)) {
          if (sub is! Directory) continue;
          final id = p.basename(sub.path);
          await for (final f in sub.list(recursive: true, followLinks: false)) {
            if (f is! File) continue;
            final rel = p.relative(f.path, from: sub.path);
            files['plugins/$id/$rel'] =
                Uint8List.fromList(await f.readAsBytes());
          }
        }
      }
    }

    await StarHopeFile.write(
      path: path,
      meta: meta,
      payload: payload,
      files: files,
    );
  }

  // ============ 导入（含防伪校验） ============
  /// 返回 (file, error)。error 非空表示校验失败应中止。
  Future<(StarHopeFile?, String?)> importAndVerify(String path) async {
    return StarHopeFile.loadAndVerify(path);
  }

  /// 将导入的题目并入题库（记录来源）。返回导入数量。
  Future<int> importQuestions(StarHopeFile file) async {
    final list = (file.payload['questions'] as List?) ?? const [];
    var count = 0;
    for (final raw in list) {
      final q = Question.fromJson(raw as Map<String, dynamic>);
      // 标记来源
      final imported = q.copyWith(
        sourceNickname: q.sourceNickname ?? file.meta.nickname,
        sourceAuthorId: q.sourceAuthorId ?? file.meta.authorId,
        sourceExportedAt:
            q.sourceExportedAt ?? file.meta.exportedAt,
        sourceSocial: file.meta.publicSocial
            ? (q.sourceSocial ??
                _encodeSocial(file.meta))
            : q.sourceSocial,
        id: CryptoService.generateId(), // 防止 ID 冲突
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _db.upsertQuestion(imported);
      count++;
    }
    return count;
  }

  // ============ 考试导入导出（.starhope 防伪） ============
  Future<void> exportExam({
    required String path,
    required List<ExamRule> rules,
    required List<Question> questions,
    required ShareMeta meta,
  }) async {
    final payload = {
      'exam_rules': rules.map((r) => r.toRow()).toList(),
      'questions': questions.map((q) => q.toJson()).toList(),
    };
    await StarHopeFile.write(path: path, meta: meta, payload: payload);
  }

  /// 导入考试规则：重新生成规则 id 防冲突；题目并入题库（重新生成 id + 来源标记），
  /// 自定义选题(questionIds)按新题目 id 重映射。
  Future<int> importExam(StarHopeFile file) async {
    final p = file.payload;
    final qOldToNew = <String, String>{};
    for (final raw in (p['questions'] as List?) ?? const []) {
      final q = Question.fromJson(raw as Map<String, dynamic>);
      final newId = CryptoService.generateId();
      qOldToNew[q.id] = newId;
      await _db.upsertQuestion(q.copyWith(
        id: newId,
        sourceNickname: q.sourceNickname ?? file.meta.nickname,
        sourceAuthorId: q.sourceAuthorId ?? file.meta.authorId,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }
    var count = 0;
    for (final raw in (p['exam_rules'] as List?) ?? const []) {
      final r = ExamRule.fromRow(raw as Map<String, dynamic>);
      final newQids = r.questionIds?.map((id) => qOldToNew[id] ?? id).toList();
      await _db.saveExamRule(ExamRule(
        id: CryptoService.generateId(),
        name: r.name,
        filter: r.filter,
        count: r.count,
        durationMinutes: r.durationMinutes,
        scorePerQuestion: r.scorePerQuestion,
        allowReviewBack: r.allowReviewBack,
        questionIds: newQids,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      count++;
    }
    return count;
  }

  String _encodeSocial(ShareMeta m) {
    final parts = <String>[];
    if (m.github != null && m.github!.isNotEmpty) parts.add('github:${m.github}');
    if (m.qq != null && m.qq!.isNotEmpty) parts.add('qq:${m.qq}');
    if (m.wechat != null && m.wechat!.isNotEmpty) parts.add('wechat:${m.wechat}');
    return parts.join(';');
  }

  // ============ 练习/考试 记录：starhope 导出导入 ============
  Future<void> exportPracticeRecord({
    required String path,
    required PracticeSession session,
    required List<Question> questions,
    required ShareMeta meta,
  }) async {
    final payload = {
      'practice': session.toJson(),
      'questions': questions.map((q) => q.toJson()).toList(),
    };
    await StarHopeFile.write(path: path, meta: meta, payload: payload);
  }

  /// 导入练习记录：题目并入题库（重新生成 id + 来源标记），session 的题目/作答 id
  /// 按映射重写，session id 重新生成防冲突。返回导入题目数。
  Future<int> importPracticeRecord(StarHopeFile file) async {
    final p = file.payload;
    final qOldToNew = <String, String>{};
    for (final raw in (p['questions'] as List?) ?? const []) {
      final q = Question.fromJson(raw as Map<String, dynamic>);
      final newId = CryptoService.generateId();
      qOldToNew[q.id] = newId;
      await _db.upsertQuestion(q.copyWith(
        id: newId,
        sourceNickname: q.sourceNickname ?? file.meta.nickname,
        sourceAuthorId: q.sourceAuthorId ?? file.meta.authorId,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }
    final sRaw = p['practice'] as Map<String, dynamic>?;
    if (sRaw != null) {
      final s = PracticeSession.fromJson(sRaw);
      final newQids =
          s.questionIds.map((id) => qOldToNew[id] ?? id).toList();
      final newAnswers = s.answers
          .map((a) => a.copyWith(
              questionId: qOldToNew[a.questionId] ?? a.questionId))
          .toList();
      await _db.savePractice(s.copyWith(
        id: CryptoService.generateId(),
        questionIds: newQids,
        answers: newAnswers,
      ));
    }
    return qOldToNew.length;
  }

  Future<void> exportExamResultRecord({
    required String path,
    required ExamResult result,
    required List<Question> questions,
    required ShareMeta meta,
  }) async {
    final payload = {
      'exam_result': result.toJson(),
      'questions': questions.map((q) => q.toJson()).toList(),
    };
    await StarHopeFile.write(path: path, meta: meta, payload: payload);
  }

  Future<int> importExamResultRecord(StarHopeFile file) async {
    final p = file.payload;
    final qOldToNew = <String, String>{};
    for (final raw in (p['questions'] as List?) ?? const []) {
      final q = Question.fromJson(raw as Map<String, dynamic>);
      final newId = CryptoService.generateId();
      qOldToNew[q.id] = newId;
      await _db.upsertQuestion(q.copyWith(
        id: newId,
        sourceNickname: q.sourceNickname ?? file.meta.nickname,
        sourceAuthorId: q.sourceAuthorId ?? file.meta.authorId,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }
    final rRaw = p['exam_result'] as Map<String, dynamic>?;
    if (rRaw != null) {
      final r = ExamResult.fromJson(rRaw);
      final newQids =
          r.questionIds.map((id) => qOldToNew[id] ?? id).toList();
      final newAnswers = r.answers
          .map((a) => a.copyWith(
              questionId: qOldToNew[a.questionId] ?? a.questionId))
          .toList();
      await _db.saveExamResult(ExamResult(
        id: CryptoService.generateId(),
        ruleId: r.ruleId,
        ruleName: r.ruleName,
        questionIds: newQids,
        answers: newAnswers,
        startedAt: r.startedAt,
        submittedAt: r.submittedAt,
        score: r.score,
        totalScore: r.totalScore,
        correctCount: r.correctCount,
        wrongCount: r.wrongCount,
        focusLostCount: r.focusLostCount,
        timeAnomaly: r.timeAnomaly,
        autoSubmitted: r.autoSubmitted,
        objectiveScore: r.objectiveScore,
        subjectiveScore: r.subjectiveScore,
        subjectiveTotal: r.subjectiveTotal,
        graded: r.graded,
        passed: r.passed,
      ));
    }
    return qOldToNew.length;
  }

  // ============ 练习/考试 记录：Markdown 可读报告（单向，不可回导） ============
  String practiceToMarkdown(PracticeSession s, List<Question> questions) {
    final map = {for (final q in questions) q.id: q};
    final correct = s.answers.where((a) => a.correct).length;
    final sb = StringBuffer();
    sb.writeln('# 练习记录');
    sb.writeln();
    sb.writeln('- 时间：${_fmtTime(s.startedAt)}');
    sb.writeln('- 模式：${s.mode == 'batch' ? '集中判题' : '边练边判'}');
    sb.writeln('- 题数：${s.questionIds.length} · 正确 $correct/${s.answers.length}');
    sb.writeln();
    for (var i = 0; i < s.questionIds.length; i++) {
      final q = map[s.questionIds[i]];
      final rec = s.answers.firstWhere(
        (a) => a.questionId == s.questionIds[i],
        orElse: () => AnswerRecord(
            questionId: s.questionIds[i],
            userAnswer: '',
            correct: false,
            usedSeconds: 0),
      );
      sb.writeln('## 第 ${i + 1} 题 ${rec.correct ? "✓" : (rec.userAnswer.isEmpty ? "（未作答）" : "✗")}');
      if (q == null) {
        sb.writeln('> 题目已不在题库\n');
        continue;
      }
      sb.writeln(q.stem);
      if (q.options.isNotEmpty) {
        for (var j = 0; j < q.options.length; j++) {
          sb.writeln('${String.fromCharCode(65 + j)}. ${q.options[j]}');
        }
      }
      sb.writeln();
      sb.writeln('- 你的答案：${QuestionSerializer.renderAnswer(q, rec.userAnswer)}');
      if (q.type != QuestionType.essay) {
        sb.writeln('- 正确答案：${QuestionSerializer.renderAnswer(q, q.answer)}');
      }
      if (q.explanation.isNotEmpty) sb.writeln('- 解析：${q.explanation}');
      sb.writeln();
    }
    return sb.toString();
  }

  String examResultToMarkdown(ExamResult r, List<Question> questions) {
    final map = {for (final q in questions) q.id: q};
    final sb = StringBuffer();
    sb.writeln('# 考试成绩单 · ${r.ruleName}');
    sb.writeln();
    sb.writeln('- 时间：${_fmtTime(r.startedAt)}');
    sb.writeln('- 得分：${r.score} / ${r.totalScore}'
        '${r.totalScore > 0 ? (r.passed ? "（通过）" : "（未通过）") : ""}');
    sb.writeln('- 正确 ${r.correctCount} · 错误 ${r.wrongCount}');
    if (r.subjectiveTotal > 0) {
      sb.writeln('- 客观 ${r.objectiveScore} · 主观 ${r.subjectiveScore}/${r.subjectiveTotal}'
          '${r.graded ? "" : "（待评）"}');
    }
    sb.writeln();
    for (var i = 0; i < r.questionIds.length; i++) {
      final q = map[r.questionIds[i]];
      final rec = r.answers.firstWhere(
        (a) => a.questionId == r.questionIds[i],
        orElse: () => AnswerRecord(
            questionId: r.questionIds[i],
            userAnswer: '',
            correct: false,
            usedSeconds: 0),
      );
      sb.writeln('## 第 ${i + 1} 题 ${rec.correct ? "✓" : "✗"}');
      if (q == null) {
        sb.writeln('> 题目已不在题库\n');
        continue;
      }
      sb.writeln(q.stem);
      if (q.options.isNotEmpty) {
        for (var j = 0; j < q.options.length; j++) {
          sb.writeln('${String.fromCharCode(65 + j)}. ${q.options[j]}');
        }
      }
      sb.writeln();
      sb.writeln('- 你的答案：${QuestionSerializer.renderAnswer(q, rec.userAnswer)}');
      if (q.type != QuestionType.essay) {
        sb.writeln('- 正确答案：${QuestionSerializer.renderAnswer(q, q.answer)}');
      }
      if (q.explanation.isNotEmpty) sb.writeln('- 解析：${q.explanation}');
      sb.writeln();
    }
    return sb.toString();
  }

  String _fmtTime(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms).toString().substring(0, 16);

  /// 从备份恢复。
  ///
  /// - [modules] 为 null：全量恢复（先 clearAll 清空全部，再全恢复）——旧行为。
  /// - [modules] 非空：**选择性恢复**，只恢复所选模块；仅清空所选模块的表与磁盘，
  ///   其它数据不动（不再一股脑 clearAll 全覆盖）。
  Future<void> restoreBackup(StarHopeFile file, {Set<String>? modules}) async {
    final p = file.payload;
    bool want(String m) => modules == null || modules.contains(m);

    // 全量恢复清空全部表；选择性恢复只清空所选模块的表。
    await _db.clearAll(modules == null ? null : DataModule.tablesFor(modules));

    // 选择性恢复时，对带磁盘文件的模块做"全量替换"：先清空其磁盘目录。
    if (modules != null) {
      if (modules.contains('materials')) {
        await FileStorageService.clearAttachments();
      }
      if (modules.contains('plugins')) {
        await _clearPluginsDir();
      }
    }

    // 题目
    if (want('questions')) {
      for (final raw in (p['questions'] as List?) ?? const []) {
        await _db.upsertQuestion(
            Question.fromJson(raw as Map<String, dynamic>));
      }
    }
    // 题库夹
    if (want('folders')) {
      for (final raw in (p['question_folders'] as List?) ?? const []) {
        await _db.saveFolder(QuestionFolder.fromRow(raw as Map<String, dynamic>));
      }
    }
    // 练习历史
    if (want('practices')) {
      for (final raw in (p['practice_sessions'] as List?) ?? const []) {
        await _db.savePractice(
            PracticeSession.fromRow(raw as Map<String, dynamic>));
      }
    }
    // 考试规则/结果
    if (want('exam_rules')) {
      for (final raw in (p['exam_rules'] as List?) ?? const []) {
        await _db.saveExamRule(ExamRule.fromRow(raw as Map<String, dynamic>));
      }
    }
    if (want('exam_results')) {
      for (final raw in (p['exam_results'] as List?) ?? const []) {
        await _db.saveExamResult(ExamResult.fromRow(raw as Map<String, dynamic>));
      }
    }
    // 错题（保真恢复：直接写完整字段，不走 recordWrong 的累加语义）
    if (want('wrong')) {
      for (final raw in (p['wrong_questions'] as List?) ?? const []) {
        final w = WrongQuestion.fromRow(raw as Map<String, dynamic>);
        if (w.questionId.isEmpty) continue;
        await _db.saveWrong(w);
      }
    }
    if (want('wrong_groups')) {
      for (final raw in (p['wrong_groups'] as List?) ?? const []) {
        await _db.saveWrongGroup(WrongGroup.fromRow(raw as Map<String, dynamic>));
      }
    }
    // 资料 + 笔记 + 文件
    if (want('materials')) {
      for (final raw in (p['materials'] as List?) ?? const []) {
        final m = raw as Map<String, dynamic>;
        final fmt = MaterialFormatX.fromExt((m['format'] as String?) ?? 'txt');
        String? storedPath;
        final fileName = '${m['id']}.$fmt';
        if (file.files.containsKey(fileName)) {
          storedPath = await _writeMaterialFile(fileName, file.files[fileName]!);
        }
        final material = ReadingMaterial(
          id: (m['id'] as String?) ?? CryptoService.generateId(),
          title: (m['title'] as String?) ?? '未命名',
          format: fmt,
          storedPath: storedPath ?? '',
          sizeBytes: (m['size_bytes'] as num?)?.toInt() ?? 0,
          sourceNickname: m['source_nickname'] as String?,
          sourceAuthorId: m['source_author_id'] as String?,
          progress: (m['progress'] as num?)?.toDouble() ?? 0,
          finished: m['finished'] as bool? ?? false,
          addedAt: (m['added_at'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
          lastReadAt: (m['last_read_at'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        );
        await _db.saveMaterial(material);
        for (final nraw in (m['notes'] as List?) ?? const []) {
          await _db.saveNote(Note.fromJson(nraw as Map<String, dynamic>).copyWith(
              id: CryptoService.generateId(), materialId: material.id));
        }
      }
    }
    // AI（服务不含密钥；智能体/对话/消息保真）
    if (want('ai_services')) {
      for (final raw in (p['ai_services'] as List?) ?? const []) {
        await _db.saveAIService(
            AIServiceConfig.fromRow(raw as Map<String, dynamic>));
      }
    }
    if (want('ai_agents')) {
      for (final raw in (p['ai_agents'] as List?) ?? const []) {
        await _db.saveAgent(AIAgent.fromRow(raw as Map<String, dynamic>));
      }
    }
    if (want('ai_conversations')) {
      for (final raw in (p['ai_conversations'] as List?) ?? const []) {
        await _db.saveConversation(
            AIConversation.fromRow(raw as Map<String, dynamic>));
      }
    }
    if (want('ai_messages')) {
      for (final raw in (p['ai_messages'] as List?) ?? const []) {
        await _db.saveMessage(AIMessage.fromRow(raw as Map<String, dynamic>));
      }
    }
    // 插件（DB 登记行 + 磁盘目录文件）
    if (want('plugins')) {
      await _restorePlugins(file);
    }
  }

  /// 删除整个 plugins 目录（DB 行由 clearAll({'plugins'}) 清理）。
  Future<void> _clearPluginsDir() async {
    final d = Directory(p.join(await StorageConfig.dataRoot(), 'plugins'));
    if (await d.exists()) await d.delete(recursive: true);
  }

  /// 从备份恢复插件：逐个写回 plugins/<id>/ 下所有文件并登记 DB 行。
  Future<void> _restorePlugins(StarHopeFile file) async {
    final rows = (file.payload['plugins'] as List?) ?? const [];
    final pluginsRoot =
        Directory(p.join(await StorageConfig.dataRoot(), 'plugins'));
    for (final raw in rows) {
      final row = raw as Map<String, dynamic>;
      final id = (row['id'] as String?) ?? '';
      if (id.isEmpty) continue;
      final dir = Directory(p.join(pluginsRoot.path, id));
      await dir.create(recursive: true);
      final prefix = 'plugins/$id/';
      for (final entry in file.files.entries) {
        if (!entry.key.startsWith(prefix)) continue;
        final rel = entry.key.substring(prefix.length);
        final f = File(p.join(dir.path, rel));
        await f.parent.create(recursive: true);
        await f.writeAsBytes(entry.value);
      }
      await _db.upsertPlugin(Map<String, Object?>.from(row));
    }
  }

  Future<String> _writeMaterialFile(String name, Uint8List bytes) async {
    return FileStorageService.writeBytes(name, bytes);
  }
}
