import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/constants.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/models/models.dart';
import '../../core/models/question.dart';
import '../../core/models/user.dart';
import '../storage_config.dart';

/// 本地数据库服务（服务层）
///
/// 桌面端通过 sqflite_common_ffi 提供 SQLite；移动端复用同一套 SQL。
/// 数据库文件存放于应用私有目录，无其他应用可读。
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  bool _initialized = false;

  Future<Database> get db async {
    if (!_initialized) await init();
    return _db!;
  }

  Future<void> init() async {
    if (_initialized) return;
    // 桌面端启用 ffi
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await StorageConfig.dataRoot();
    final dbPath = p.join(dir, 'starhope.db');
    _db = await openDatabase(
      dbPath,
      version: 8,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _initialized = true;
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    // 用户（本地单账户，仅一行）
    batch.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        account TEXT NOT NULL,
        nickname TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        avatar_path TEXT,
        github TEXT,
        qq TEXT,
        wechat TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    // 题库
    batch.execute('''
      CREATE TABLE questions (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        stem TEXT NOT NULL,
        options TEXT NOT NULL,
        answer TEXT NOT NULL,
        explanation TEXT,
        tags TEXT,
        difficulty INTEGER DEFAULT 3,
        source_nickname TEXT,
        source_author_id TEXT,
        source_social TEXT,
        source_exported_at TEXT,
        folder_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        practice_count INTEGER DEFAULT 0,
        correct_count INTEGER DEFAULT 0,
        last_practiced_at INTEGER
      )
    ''');
    batch.execute(
        'CREATE INDEX idx_questions_type ON questions(type)');
    batch.execute(
        'CREATE INDEX idx_questions_source ON questions(source_author_id)');
    batch.execute(
        'CREATE INDEX idx_questions_folder ON questions(folder_id)');
    // 题库夹（多层嵌套：parent_id 自引用）
    batch.execute('''
      CREATE TABLE question_folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id TEXT,
        created_at INTEGER NOT NULL,
        sort_order INTEGER DEFAULT 0
      )
    ''');
    // 练习会话
    batch.execute('''
      CREATE TABLE practice_sessions (
        id TEXT PRIMARY KEY,
        filter_json TEXT,
        question_ids TEXT,
        answers_json TEXT,
        current_index INTEGER DEFAULT 0,
        started_at INTEGER NOT NULL,
        finished_at INTEGER,
        status TEXT,
        mode TEXT DEFAULT 'instant'
      )
    ''');
    // 考试规则
    batch.execute('''
      CREATE TABLE exam_rules (
        id TEXT PRIMARY KEY,
        name TEXT,
        filter_json TEXT,
        count INTEGER,
        duration_minutes INTEGER,
        score_per_question INTEGER DEFAULT 5,
        allow_review_back INTEGER DEFAULT 1,
        question_ids_json TEXT,
        anti_cheat INTEGER DEFAULT 0,
        type_quotas_json TEXT,
        pass_rate REAL DEFAULT 0.6,
        created_at INTEGER NOT NULL
      )
    ''');
    // 考试结果
    batch.execute('''
      CREATE TABLE exam_results (
        id TEXT PRIMARY KEY,
        rule_id TEXT,
        rule_name TEXT,
        question_ids TEXT,
        answers_json TEXT,
        started_at INTEGER,
        submitted_at INTEGER,
        score INTEGER,
        total_score INTEGER,
        correct_count INTEGER,
        wrong_count INTEGER,
        focus_lost_count INTEGER DEFAULT 0,
        time_anomaly INTEGER DEFAULT 0,
        auto_submitted INTEGER DEFAULT 0,
        objective_score INTEGER DEFAULT 0,
        subjective_score INTEGER DEFAULT 0,
        subjective_total INTEGER DEFAULT 0,
        graded INTEGER DEFAULT 1,
        passed INTEGER DEFAULT 0
      )
    ''');
    // 错题本
    batch.execute('''
      CREATE TABLE wrong_questions (
        id TEXT PRIMARY KEY,
        question_id TEXT NOT NULL,
        wrong_count INTEGER DEFAULT 1,
        last_wrong_at INTEGER,
        first_wrong_at INTEGER,
        mastery INTEGER DEFAULT 0,
        last_practiced_at INTEGER,
        custom_group TEXT,
        consecutive_correct INTEGER DEFAULT 0,
        source_session_id TEXT,
        source_session_type TEXT,
        source_session_name TEXT,
        UNIQUE(question_id)
      )
    ''');
    // 错题自定义分组
    batch.execute('''
      CREATE TABLE wrong_groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    // AI 服务配置
    batch.execute('''
      CREATE TABLE ai_services (
        id TEXT PRIMARY KEY,
        name TEXT,
        type TEXT,
        base_url TEXT,
        model TEXT,
        api_key_encrypted TEXT,
        has_api_key INTEGER DEFAULT 0
      )
    ''');
    // AI 对话
    batch.execute('''
      CREATE TABLE ai_conversations (
        id TEXT PRIMARY KEY,
        title TEXT,
        service_id TEXT,
        agent_id TEXT,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');
    batch.execute('''
      CREATE TABLE ai_messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT,
        role TEXT,
        content TEXT,
        attachments_json TEXT,
        created_at INTEGER
      )
    ''');
    batch.execute(
        'CREATE INDEX idx_ai_messages_conv ON ai_messages(conversation_id)');
    // AI 智能体（人格配置：引用 ai_services，附加系统提示词/模型覆盖/模型参数）
    batch.execute('''
      CREATE TABLE ai_agents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        avatar_path TEXT,
        system_prompt TEXT,
        service_id TEXT NOT NULL,
        model TEXT,
        temperature REAL,
        top_p REAL,
        max_tokens INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');
    batch.execute(
        'CREATE INDEX idx_ai_agents_service ON ai_agents(service_id)');
    // 阅读资料
    batch.execute('''
      CREATE TABLE reading_materials (
        id TEXT PRIMARY KEY,
        title TEXT,
        format TEXT,
        stored_path TEXT,
        size_bytes INTEGER,
        source_nickname TEXT,
        source_author_id TEXT,
        progress REAL DEFAULT 0,
        finished INTEGER DEFAULT 0,
        added_at INTEGER,
        last_read_at INTEGER
      )
    ''');
    // 笔记
    batch.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        material_id TEXT NOT NULL,
        type TEXT,
        page_index INTEGER DEFAULT 0,
        payload TEXT,
        text TEXT,
        is_original INTEGER DEFAULT 0,
        source_nickname TEXT,
        created_at INTEGER
      )
    ''');
    batch.execute('CREATE INDEX idx_notes_material ON notes(material_id)');
    // 插件
    batch.execute('''
      CREATE TABLE plugins (
        id TEXT PRIMARY KEY,
        dir_name TEXT NOT NULL,
        display_name TEXT NOT NULL,
        version TEXT,
        author TEXT,
        description TEXT,
        manifest_sha256 TEXT,
        enabled INTEGER DEFAULT 0,
        params_json TEXT,
        installed_at INTEGER NOT NULL,
        updated_at INTEGER
      )
    ''');
    await batch.commit(noResult: true);
  }

  /// 数据库升级迁移（阶梯式：每个 version 分支累加 schema 变更）
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v2：AI 多智能体 + 附件
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE ai_conversations ADD COLUMN agent_id TEXT');
      await db.execute(
          'ALTER TABLE ai_messages ADD COLUMN attachments_json TEXT');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ai_agents (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          avatar_path TEXT,
          system_prompt TEXT,
          service_id TEXT NOT NULL,
          model TEXT,
          temperature REAL,
          top_p REAL,
          max_tokens INTEGER,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ai_agents_service ON ai_agents(service_id)');
    }
    // v3：题库夹（多层嵌套）
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE questions ADD COLUMN folder_id TEXT');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_questions_folder ON questions(folder_id)');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS question_folders (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          parent_id TEXT,
          created_at INTEGER NOT NULL,
          sort_order INTEGER DEFAULT 0
        )
      ''');
    }
    // v4：错题本掌握度/自定义分组
    if (oldVersion < 4) {
      await db.execute(
          'ALTER TABLE wrong_questions ADD COLUMN mastery INTEGER DEFAULT 0');
      await db.execute(
          'ALTER TABLE wrong_questions ADD COLUMN last_practiced_at INTEGER');
      await db.execute(
          'ALTER TABLE wrong_questions ADD COLUMN custom_group TEXT');
      await db.execute(
          'ALTER TABLE wrong_questions ADD COLUMN consecutive_correct INTEGER DEFAULT 0');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS wrong_groups (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
    }
    // v5：错题答题来源 + 考试自定义选题/主客观分项判分
    if (oldVersion < 5) {
      await db.execute(
          'ALTER TABLE wrong_questions ADD COLUMN source_session_id TEXT');
      await db.execute(
          'ALTER TABLE wrong_questions ADD COLUMN source_session_type TEXT');
      await db.execute(
          'ALTER TABLE wrong_questions ADD COLUMN source_session_name TEXT');
      await db.execute(
          'ALTER TABLE exam_rules ADD COLUMN question_ids_json TEXT');
      await db.execute(
          'ALTER TABLE exam_results ADD COLUMN objective_score INTEGER DEFAULT 0');
      await db.execute(
          'ALTER TABLE exam_results ADD COLUMN subjective_score INTEGER DEFAULT 0');
      await db.execute(
          'ALTER TABLE exam_results ADD COLUMN subjective_total INTEGER DEFAULT 0');
      await db.execute(
          'ALTER TABLE exam_results ADD COLUMN graded INTEGER DEFAULT 1');
    }
    // v6：考试防作弊开关
    if (oldVersion < 6) {
      await db.execute(
          'ALTER TABLE exam_rules ADD COLUMN anti_cheat INTEGER DEFAULT 0');
    }
    // v7：练习判题模式 + 题目使用统计 + 考试题型配额/及格线 + 成绩通过判定
    if (oldVersion < 7) {
      await db.execute(
          "ALTER TABLE practice_sessions ADD COLUMN mode TEXT DEFAULT 'instant'");
      await db.execute(
          'ALTER TABLE questions ADD COLUMN practice_count INTEGER DEFAULT 0');
      await db.execute(
          'ALTER TABLE questions ADD COLUMN correct_count INTEGER DEFAULT 0');
      await db.execute(
          'ALTER TABLE questions ADD COLUMN last_practiced_at INTEGER');
      await db.execute(
          'ALTER TABLE exam_rules ADD COLUMN type_quotas_json TEXT');
      await db.execute(
          'ALTER TABLE exam_rules ADD COLUMN pass_rate REAL DEFAULT 0.6');
      await db.execute(
          'ALTER TABLE exam_results ADD COLUMN passed INTEGER DEFAULT 0');
    }
    // v8：插件系统
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS plugins (
          id TEXT PRIMARY KEY,
          dir_name TEXT NOT NULL,
          display_name TEXT NOT NULL,
          version TEXT,
          author TEXT,
          description TEXT,
          manifest_sha256 TEXT,
          enabled INTEGER DEFAULT 0,
          params_json TEXT,
          installed_at INTEGER NOT NULL,
          updated_at INTEGER
        )
      ''');
    }
  }

  // ============ 用户 ============
  Future<User?> loadUser() async {
    final d = await db;
    final rows = await d.query('users', limit: 1);
    if (rows.isEmpty) return null;
    return User.fromRow(rows.first);
  }

  Future<void> saveUser(User u) async {
    final d = await db;
    await d.insert('users', u.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 清空用户表（一键清空/恢复出厂用）
  Future<void> deleteUser() async {
    final d = await db;
    await d.delete('users');
  }

  // ============ 题目 ============
  Future<List<Question>> allQuestions() async {
    final d = await db;
    final rows = await d.query('questions', orderBy: 'created_at DESC');
    return rows.map(Question.fromRow).toList();
  }

  Future<Question?> getQuestion(String id) async {
    final d = await db;
    final rows =
        await d.query('questions', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Question.fromRow(rows.first);
  }

  Future<List<Question>> queryQuestions({
    List<String> tags = const [],
    List<QuestionType> types = const [],
    String? sourceAuthorId,
    String keyword = '',
    List<String> folderIds = const [],
    int? limit,
  }) async {
    final d = await db;
    final where = <String>[];
    final args = <Object?>[];
    if (folderIds.isNotEmpty) {
      where.add('folder_id IN (${folderIds.map((_) => '?').join(',')})');
      args.addAll(folderIds);
    }
    if (types.isNotEmpty) {
      where.add('type IN (${types.map((_) => '?').join(',')})');
      args.addAll(types.map((t) => t.name));
    }
    if (sourceAuthorId != null && sourceAuthorId.isNotEmpty) {
      where.add('source_author_id = ?');
      args.add(sourceAuthorId);
    }
    if (keyword.isNotEmpty) {
      where.add('(stem LIKE ? OR explanation LIKE ?)');
      args.addAll(['%$keyword%', '%$keyword%']);
    }
    String? w = where.isEmpty ? null : where.join(' AND ');
    var rows = await d.query('questions',
        where: w, whereArgs: args, orderBy: 'created_at DESC');
    var result = rows.map(Question.fromRow).toList();
    // 标签在应用层过滤（标签以逗号存储）
    if (tags.isNotEmpty) {
      result = result
          .where((q) => tags.any((t) => q.tags.contains(t)))
          .toList();
    }
    if (limit != null && result.length > limit) {
      result = result.sublist(0, limit);
    }
    return result;
  }

  Future<void> upsertQuestion(Question q) async {
    final d = await db;
    await d.insert('questions', q.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteQuestions(List<String> ids) async {
    if (ids.isEmpty) return;
    final d = await db;
    final placeholders = ids.map((_) => '?').join(',');
    await d.delete('questions',
        where: 'id IN ($placeholders)', whereArgs: ids);
  }

  Future<List<String>> allTags() async {
    final d = await db;
    final rows = await d.query('questions', columns: ['tags']);
    final set = <String>{};
    for (final r in rows) {
      final s = (r['tags'] as String?) ?? '';
      for (final t in s.split(',')) {
        final tt = t.trim();
        if (tt.isNotEmpty) set.add(tt);
      }
    }
    return set.toList()..sort();
  }

  Future<List<String>> allSources() async {
    final d = await db;
    final rows = await d.query('questions',
        columns: ['source_nickname', 'source_author_id'],
        distinct: true,
        where: "source_author_id != ''");
    return rows
        .map((r) => (r['source_nickname'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  // ============ 题库夹 ============
  Future<void> saveFolder(QuestionFolder f) async {
    final d = await db;
    await d.insert('question_folders', f.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<QuestionFolder>> allFolders() async {
    final d = await db;
    final rows = await d.query('question_folders',
        orderBy: 'sort_order ASC, created_at ASC');
    return rows.map(QuestionFolder.fromRow).toList();
  }

  /// 删除夹：夹内题目 folder_id 置空（移到根），子夹 parent_id 置空（移到根）
  Future<void> deleteFolder(String id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.update('questions', {'folder_id': null},
          where: 'folder_id = ?', whereArgs: [id]);
      await txn.update('question_folders', {'parent_id': ''},
          where: 'parent_id = ?', whereArgs: [id]);
      await txn.delete('question_folders', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// 批量移动题目到指定夹（folderId 为 null/空 = 移到根）
  Future<void> moveQuestionsToFolder(List<String> ids, String? folderId) async {
    if (ids.isEmpty) return;
    final d = await db;
    final placeholders = ids.map((_) => '?').join(',');
    await d.update('questions', {'folder_id': folderId},
        where: 'id IN ($placeholders)', whereArgs: ids);
  }

  // ============ 练习 ============
  Future<void> savePractice(PracticeSession s) async {
    final d = await db;
    await d.insert('practice_sessions', s.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PracticeSession>> allPractices() async {
    final d = await db;
    final rows =
        await d.query('practice_sessions', orderBy: 'started_at DESC');
    return rows.map(PracticeSession.fromRow).toList();
  }

  Future<void> deletePractice(String id) async {
    final d = await db;
    await d.delete('practice_sessions', where: 'id = ?', whereArgs: [id]);
  }

  // ============ 考试 ============
  Future<void> saveExamRule(ExamRule r) async {
    final d = await db;
    await d.insert('exam_rules', r.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ExamRule>> allExamRules() async {
    final d = await db;
    final rows = await d.query('exam_rules', orderBy: 'created_at DESC');
    return rows.map(ExamRule.fromRow).toList();
  }

  Future<void> deleteExamRule(String id) async {
    final d = await db;
    await d.delete('exam_rules', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveExamResult(ExamResult r) async {
    final d = await db;
    await d.insert('exam_results', r.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ExamResult>> allExamResults() async {
    final d = await db;
    final rows = await d.query('exam_results', orderBy: 'submitted_at DESC');
    return rows.map(ExamResult.fromRow).toList();
  }

  Future<void> deleteExamResult(String id) async {
    final d = await db;
    await d.delete('exam_results', where: 'id = ?', whereArgs: [id]);
  }

  // ============ 错题 ============
  /// 更新题目使用统计：每次作答 practice_count+1、刷新 last_practiced_at；答对再 correct_count+1。
  Future<void> _bumpQuestionStats(String questionId,
      {required bool correct, required int now}) async {
    final d = await db;
    final rows = await d.query('questions',
        where: 'id = ?',
        whereArgs: [questionId],
        columns: ['practice_count', 'correct_count'],
        limit: 1);
    if (rows.isEmpty) return;
    final pc = ((rows.first['practice_count'] as int?) ?? 0) + 1;
    final cc = ((rows.first['correct_count'] as int?) ?? 0) + (correct ? 1 : 0);
    await d.update(
        'questions',
        {
          'practice_count': pc,
          'correct_count': cc,
          'last_practiced_at': now
        },
        where: 'id = ?',
        whereArgs: [questionId]);
  }

  Future<void> recordWrong(String questionId, int now,
      {String? sourceSessionId,
      String? sourceSessionType,
      String? sourceSessionName}) async {
    final d = await db;
    await _bumpQuestionStats(questionId, correct: false, now: now);
    final existing = await d.query('wrong_questions',
        where: 'question_id = ?', whereArgs: [questionId], limit: 1);
    if (existing.isEmpty) {
      await d.insert('wrong_questions', {
        'id': CryptoServiceId.gen(),
        'question_id': questionId,
        'wrong_count': 1,
        'last_wrong_at': now,
        'first_wrong_at': now,
        if (sourceSessionId != null) 'source_session_id': sourceSessionId,
        if (sourceSessionType != null) 'source_session_type': sourceSessionType,
        if (sourceSessionName != null) 'source_session_name': sourceSessionName,
      });
    } else {
      final count = ((existing.first['wrong_count'] as int?) ?? 1) + 1;
      // 再次答错：连续答对归零、掌握度回到未掌握，刷新来源为最近一次
      await d.update(
          'wrong_questions',
          {
            'wrong_count': count,
            'last_wrong_at': now,
            'consecutive_correct': 0,
            'mastery': 0,
            if (sourceSessionId != null) 'source_session_id': sourceSessionId,
            if (sourceSessionType != null)
              'source_session_type': sourceSessionType,
            if (sourceSessionName != null)
              'source_session_name': sourceSessionName,
          },
          where: 'question_id = ?',
          whereArgs: [questionId]);
    }
  }

  /// 答对一题：连续答对 +1，达阈值自动移出错题本；否则升级掌握度并记录练习时间。
  Future<void> recordCorrect(String questionId, int now,
      {int threshold = 3}) async {
    final d = await db;
    await _bumpQuestionStats(questionId, correct: true, now: now);
    final existing = await d.query('wrong_questions',
        where: 'question_id = ?', whereArgs: [questionId], limit: 1);
    if (existing.isEmpty) return; // 不在错题本，无需处理
    final consecutive =
        ((existing.first['consecutive_correct'] as int?) ?? 0) + 1;
    if (consecutive >= threshold) {
      await d.delete('wrong_questions',
          where: 'question_id = ?', whereArgs: [questionId]);
      return;
    }
    final mastery = (existing.first['mastery'] as int?) ?? 0;
    await d.update(
        'wrong_questions',
        {
          'consecutive_correct': consecutive,
          'last_practiced_at': now,
          'mastery': mastery < 1 ? 1 : mastery,
        },
        where: 'question_id = ?',
        whereArgs: [questionId]);
  }

  Future<void> setMastery(String questionId, int level) async {
    final d = await db;
    await d.update('wrong_questions', {'mastery': level},
        where: 'question_id = ?', whereArgs: [questionId]);
  }

  Future<void> setWrongGroup(String questionId, String? group) async {
    final d = await db;
    await d.update('wrong_questions', {'custom_group': group},
        where: 'question_id = ?', whereArgs: [questionId]);
  }

  Future<void> clearWrong(String questionId) async {
    final d = await db;
    await d.delete('wrong_questions',
        where: 'question_id = ?', whereArgs: [questionId]);
  }

  Future<List<WrongQuestion>> allWrong() async {
    final d = await db;
    final rows =
        await d.query('wrong_questions', orderBy: 'last_wrong_at DESC');
    return rows.map(WrongQuestion.fromRow).toList();
  }

  /// 直接写入完整错题记录（恢复备份时保真用，不走 recordWrong 的累加语义）
  Future<void> saveWrong(WrongQuestion w) async {
    final d = await db;
    await d.insert('wrong_questions', w.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---- 错题自定义分组 ----
  Future<void> saveWrongGroup(WrongGroup g) async {
    final d = await db;
    await d.insert('wrong_groups', g.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<WrongGroup>> allWrongGroups() async {
    final d = await db;
    final rows = await d.query('wrong_groups', orderBy: 'created_at ASC');
    return rows.map(WrongGroup.fromRow).toList();
  }

  Future<void> deleteWrongGroup(String id) async {
    final d = await db;
    await d.delete('wrong_groups', where: 'id = ?', whereArgs: [id]);
  }

  // ============ AI ============
  Future<void> saveAgent(AIAgent a) async {
    final d = await db;
    await d.insert('ai_agents', a.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<AIAgent>> allAgents() async {
    final d = await db;
    final rows = await d.query('ai_agents', orderBy: 'created_at ASC');
    return rows.map(AIAgent.fromRow).toList();
  }

  Future<void> deleteAgent(String id) async {
    final d = await db;
    await d.delete('ai_agents', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveAIService(AIServiceConfig s) async {
    final d = await db;
    await d.insert('ai_services', s.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<AIServiceConfig>> allAIServices() async {
    final d = await db;
    final rows = await d.query('ai_services', orderBy: 'name');
    return rows.map(AIServiceConfig.fromRow).toList();
  }

  Future<void> deleteAIService(String id) async {
    final d = await db;
    await d.delete('ai_services', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveConversation(AIConversation c) async {
    final d = await db;
    await d.insert('ai_conversations', c.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<AIConversation>> allConversations() async {
    final d = await db;
    final rows =
        await d.query('ai_conversations', orderBy: 'updated_at DESC');
    return rows.map(AIConversation.fromRow).toList();
  }

  Future<void> deleteConversation(String id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('ai_messages',
          where: 'conversation_id = ?', whereArgs: [id]);
      await txn.delete('ai_conversations',
          where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> saveMessage(AIMessage m) async {
    final d = await db;
    await d.insert('ai_messages', m.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<AIMessage>> messagesOf(String conversationId) async {
    final d = await db;
    final rows = await d.query('ai_messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'created_at ASC');
    return rows.map(AIMessage.fromRow).toList();
  }

  // ============ 阅读资料 ============
  Future<void> saveMaterial(ReadingMaterial m) async {
    final d = await db;
    await d.insert('reading_materials', m.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ReadingMaterial>> allMaterials() async {
    final d = await db;
    final rows =
        await d.query('reading_materials', orderBy: 'last_read_at DESC');
    return rows.map(ReadingMaterial.fromRow).toList();
  }

  Future<void> deleteMaterial(String id) async {
    final d = await db;
    await d.delete('reading_materials', where: 'id = ?', whereArgs: [id]);
  }

  // ============ 笔记 ============
  Future<void> saveNote(Note n) async {
    final d = await db;
    await d.insert('notes', n.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Note>> notesOf(String materialId) async {
    final d = await db;
    final rows = await d.query('notes',
        where: 'material_id = ?',
        whereArgs: [materialId],
        orderBy: 'page_index ASC, created_at ASC');
    return rows.map(Note.fromRow).toList();
  }

  Future<void> deleteNote(String id) async {
    final d = await db;
    await d.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  // ============ 插件 ============
  Future<List<Map<String, Object?>>> loadPlugins() async {
    final d = await db;
    return d.query('plugins', orderBy: 'installed_at DESC');
  }

  Future<Map<String, Object?>?> getPlugin(String id) async {
    final d = await db;
    final rows = await d.query('plugins',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertPlugin(Map<String, Object?> plugin) async {
    final d = await db;
    await d.insert('plugins', plugin,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setPluginEnabled(String id, bool enabled) async {
    final d = await db;
    await d.update(
      'plugins',
      {
        'enabled': enabled ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setPluginParams(String id, String paramsJson) async {
    final d = await db;
    await d.update(
      'plugins',
      {
        'params_json': paramsJson,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deletePlugin(String id) async {
    final d = await db;
    await d.delete('plugins', where: 'id = ?', whereArgs: [id]);
  }

  // ============ 备份/恢复 ============
  Future<void> clearAll([Set<String>? tables]) async {
    final d = await db;
    const all = {
      'questions',
      'question_folders',
      'practice_sessions',
      'exam_rules',
      'exam_results',
      'wrong_questions',
      'wrong_groups',
      'ai_services',
      'ai_agents',
      'ai_conversations',
      'ai_messages',
      'reading_materials',
      'notes',
      'plugins',
    };
    final t = tables ?? all;
    await d.transaction((txn) async {
      for (final name in t) {
        await txn.delete(name);
      }
    });
  }
}

/// 简单 ID 生成器（委托加密级随机，避免碰撞）
class CryptoServiceId {
  static String gen() => CryptoService.generateId();
}

// 引用常量避免 lint 未使用
// ignore: unused_element
const int _kVer = AppConstants.formatVersion;
