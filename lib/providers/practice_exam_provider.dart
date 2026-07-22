import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/crypto/crypto_service.dart';
import '../core/models/models.dart';
import '../core/models/question.dart';
import '../services/database/database.dart';
import '../services/window_service.dart';

/// 判题逻辑（核心层算法）
class Grader {
  /// 判定单题作答是否正确
  static bool judge(Question q, String userAnswer) {
    final ua = userAnswer.trim();
    switch (q.type) {
      case QuestionType.single:
      case QuestionType.judge:
        return _normIndex(ua) == _normIndex(q.answer);
      case QuestionType.multiple:
      case QuestionType.undefined:
        final a = _indexSet(ua);
        final b = _indexSet(q.answer);
        return a.length == b.length && a.containsAll(b);
      case QuestionType.fill:
        // 多空以 || 分隔，任一空答案匹配即可（不区分大小写、去首尾空格）
        final blanks = q.answer.split('||');
        final userBlanks = ua.split('||');
        if (userBlanks.length != blanks.length) {
          // 单空作答按整体匹配
          return blanks.any((b) =>
              b.trim().toLowerCase() == ua.toLowerCase());
        }
        for (var i = 0; i < blanks.length; i++) {
          final acceptables = blanks[i].split('|||'); // 同一空多可接受答案
          final u = i < userBlanks.length ? userBlanks[i].trim().toLowerCase() : '';
          if (!acceptables.any((a) => a.trim().toLowerCase() == u)) {
            return false;
          }
        }
        return true;
      case QuestionType.essay:
        // 主观题不自动判分（考后人工评卷），判题阶段视为未对
        return false;
    }
  }

  static String _normIndex(String s) {
    final i = _indexSet(s);
    return (i.toList()..sort()).join(',');
  }

  static Set<int> _indexSet(String s) {
    final out = <int>{};
    for (final ch in s.toUpperCase().split('')) {
      if (ch.codeUnitAt(0) >= 65 && ch.codeUnitAt(0) <= 90) {
        out.add(ch.codeUnitAt(0) - 65);
      }
    }
    for (final m in RegExp(r'\d+').allMatches(s)) {
      out.add(int.parse(m.group(0)!));
    }
    return out;
  }
}

/// 考试防作弊监控
class AntiCheatMonitor {
  final void Function(int lostCount) onFocusLost;
  final void Function() onAwayTimeout;
  final void Function(bool anomaly) onClockAnomaly;

  int _focusLost = 0;
  DateTime? _lastFocusTime;
  Timer? _awayTimer;
  final DateTime _startWallClock;
  final Stopwatch _stopwatch = Stopwatch()..start();

  AntiCheatMonitor({
    required this.onFocusLost,
    required this.onAwayTimeout,
    required this.onClockAnomaly,
    DateTime? startNow,
  }) : _startWallClock = startNow ?? DateTime.now();

  /// 窗口/应用获得焦点
  void onFocusGained() {
    if (_lastFocusTime != null) {
      final away = DateTime.now().difference(_lastFocusTime!).inSeconds;
      if (away > AppConstants.examFocusGraceSeconds) {
        _focusLost++;
        onFocusLost(_focusLost);
      }
      if (away >= AppConstants.examMaxAwaySeconds) {
        _awayTimer?.cancel();
        onAwayTimeout();
      }
    }
    _lastFocusTime = null;
    _awayTimer?.cancel();
  }

  /// 窗口/应用失去焦点
  void onFocusLostEvent() {
    _lastFocusTime = DateTime.now();
    _awayTimer?.cancel();
    _awayTimer = Timer(
        const Duration(seconds: AppConstants.examMaxAwaySeconds), onAwayTimeout);
  }

  /// 检测系统时间异常：逻辑计时器与系统时钟差值校验
  void checkClock() {
    final wallElapsed =
        DateTime.now().difference(_startWallClock).inMilliseconds;
    final logicElapsed = _stopwatch.elapsedMilliseconds;
    final drift = (wallElapsed - logicElapsed).abs();
    if (drift > AppConstants.examClockDriftToleranceMs) {
      onClockAnomaly(true);
    }
  }

  int get focusLostCount => _focusLost;

  void dispose() {
    _awayTimer?.cancel();
    _stopwatch.stop();
  }
}

/// 练习与考试状态 Provider
class PracticeExamProvider extends ChangeNotifier {
  final AppDatabase _db = AppDatabase.instance;

  // 练习会话
  PracticeSession? _practice;
  PracticeSession? get practice => _practice;
  List<PracticeSession> get practiceHistory => _practiceHistory;
  List<PracticeSession> _practiceHistory = [];

  // 错题计数（只统计题库中仍存在的错题；摘要实时展示用）
  int _wrongCount = 0;
  int get wrongCount => _wrongCount;

  // 考试
  List<ExamRule> _rules = [];
  List<ExamResult> _results = [];
  ExamRule? _activeRule;
  List<Question> _examQuestions = [];
  int _examIndex = 0;
  Map<String, String> _examAnswers = {};
  final Set<String> _examReview = {}; // 考试中标记「待复习」的题目 id
  DateTime? _examStart;
  int _examRemainingSec = 0;
  Timer? _examTimer;
  AntiCheatMonitor? _antiCheat;
  int _focusLost = 0;
  bool _timeAnomaly = false;

  List<ExamRule> get rules => _rules;
  List<ExamResult> get results => _results;
  ExamRule? get activeRule => _activeRule;
  List<Question> get examQuestions => _examQuestions;
  int get examIndex => _examIndex;
  Map<String, String> get examAnswers => _examAnswers;
  int get examRemainingSec => _examRemainingSec;
  int get focusLost => _focusLost;
  bool get timeAnomaly => _timeAnomaly;
  bool get inExam => _activeRule != null;
  Set<String> get examReview => _examReview;

  void toggleExamReview(String qid) {
    if (_examReview.contains(qid)) {
      _examReview.remove(qid);
    } else {
      _examReview.add(qid);
    }
    notifyListeners();
  }

  // ============ 练习 ============
  Future<void> startPractice(List<Question> questions,
      {QuestionFilter filter = const QuestionFilter(),
      String mode = 'instant'}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = PracticeSession(
      id: CryptoService.generateId(),
      filter: filter,
      questionIds: questions.map((q) => q.id).toList(),
      startedAt: now,
      mode: mode,
    );
    _practice = session;
    _pendingAnswers.clear();
    await _db.savePractice(session);
    notifyListeners();
  }

  /// 继续未完成的练习（载入历史会话）。batch 模式同时恢复未提交答案。
  Future<void> resumePractice(String sessionId) async {
    final all = await _db.allPractices();
    PracticeSession? found;
    for (final s in all) {
      if (s.id == sessionId) {
        found = s;
        break;
      }
    }
    if (found == null) return;
    _practice = found;
    _pendingAnswers.clear();
    if (found.mode == 'batch') {
      for (final a in found.answers) {
        _pendingAnswers[a.questionId] = a.userAnswer;
      }
    }
    notifyListeners();
  }

  /// 集中判题模式：保存单题作答进度（持久化，支持中断后续练）。
  Future<void> saveBatchAnswer(String questionId, String answer) async {
    if (_practice == null) return;
    _pendingAnswers[questionId] = answer;
    final updated = _practice!.copyWith(answers: _pendingAsRecords());
    _practice = updated;
    await _db.savePractice(updated);
    notifyListeners();
  }

  List<AnswerRecord> _pendingAsRecords() => _pendingAnswers.entries
      .map((e) => AnswerRecord(
          questionId: e.key,
          userAnswer: e.value,
          correct: false,
          usedSeconds: 0,
          graded: false))
      .toList();

  /// 集中判题模式：收卷——遍历全部作答判分、记录错题、保存、返回答题记录。
  Future<List<AnswerRecord>> finishBatchPractice() async {
    if (_practice == null) return const [];
    final session = _practice!;
    final all = await _db.allQuestions();
    final map = {for (final q in all) q.id: q};
    final now = DateTime.now().millisecondsSinceEpoch;
    final records = <AnswerRecord>[];
    for (final qid in session.questionIds) {
      final q = map[qid];
      if (q == null) continue;
      final ua = _pendingAnswers[qid] ?? '';
      final correct = Grader.judge(q, ua);
      records.add(AnswerRecord(
          questionId: qid, userAnswer: ua, correct: correct, usedSeconds: 0));
      if (correct) {
        await _db.recordCorrect(qid, now);
      } else {
        await _db.recordWrong(qid, now,
            sourceSessionId: session.id,
            sourceSessionType: 'practice',
            sourceSessionName: '练习');
      }
    }
    final updated = session.copyWith(
      answers: records,
      currentIndex: session.questionIds.length,
      finishedAt: now,
      status: 'finished',
    );
    _practice = updated;
    await _db.savePractice(updated);
    await loadHistory();
    _pendingAnswers.clear();
    notifyListeners();
    return records;
  }

  void setPracticeAnswer(String questionId, String answer) {
    if (_practice == null) return;
    // 简化：暂存到内存，提交时持久化
    _pendingAnswers[questionId] = answer;
    notifyListeners();
  }

  final Map<String, String> _pendingAnswers = {};
  Map<String, String> get pendingAnswers => _pendingAnswers;

  Future<void> submitPracticeAnswer(
      Question q, String answer, int usedSeconds) async {
    if (_practice == null) return;
    final correct = Grader.judge(q, answer);
    final record = AnswerRecord(
        questionId: q.id,
        userAnswer: answer,
        correct: correct,
        usedSeconds: usedSeconds);
    final updated = _practice!.copyWith(
      answers: [..._practice!.answers.where((a) => a.questionId != q.id), record],
      currentIndex: max(_practice!.currentIndex, _practice!.answers.length),
    );
    _practice = updated;
    await _db.savePractice(updated);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (correct) {
      await _db.recordCorrect(q.id, now);
    } else {
      await _db.recordWrong(q.id, now,
          sourceSessionId: _practice!.id,
          sourceSessionType: 'practice',
          sourceSessionName: '练习');
    }
    notifyListeners();
  }

  Future<void> advancePractice() async {
    if (_practice == null) return;
    final updated =
        _practice!.copyWith(currentIndex: _practice!.currentIndex + 1);
    _practice = updated;
    await _db.savePractice(updated);
    notifyListeners();
  }

  /// 跳转到指定题号（集中判题/继续练习用）。
  Future<void> advanceTo(int idx) async {
    if (_practice == null) return;
    final updated = _practice!.copyWith(currentIndex: idx);
    _practice = updated;
    await _db.savePractice(updated);
    notifyListeners();
  }

  Future<void> finishPractice() async {
    if (_practice == null) return;
    final updated = _practice!.copyWith(
      finishedAt: DateTime.now().millisecondsSinceEpoch,
      status: 'finished',
    );
    _practice = updated;
    await _db.savePractice(updated);
    await loadHistory();
    notifyListeners();
  }

  void clearPractice() {
    _practice = null;
    _pendingAnswers.clear();
    notifyListeners();
  }

  Future<void> loadHistory() async {
    _practiceHistory = await _db.allPractices();
    await _refreshWrongCount();
    notifyListeners();
  }

  /// 重算错题计数：只统计题库中仍存在题目的错题（与错题本展示一致）。
  Future<void> _refreshWrongCount() async {
    final wrong = await _db.allWrong();
    final all = await _db.allQuestions();
    final qids = all.map((q) => q.id).toSet();
    _wrongCount = wrong.where((w) => qids.contains(w.questionId)).length;
  }

  Future<void> deletePractice(String id) async {
    await _db.deletePractice(id);
    await loadHistory();
  }

  // ============ 考试 ============
  Future<void> loadRulesAndResults() async {
    _rules = await _db.allExamRules();
    _results = await _db.allExamResults();
    await _refreshWrongCount();
    notifyListeners();
  }

  Future<void> saveRule(ExamRule r) async {
    await _db.saveExamRule(r);
    await loadRulesAndResults();
  }

  Future<void> deleteRule(String id) async {
    await _db.deleteExamRule(id);
    await loadRulesAndResults();
  }

  Future<void> deleteExamResult(String id) async {
    await _db.deleteExamResult(id);
    await loadRulesAndResults();
  }

  /// 开始考试
  Future<void> startExam(ExamRule rule, List<Question> questions) async {
    _activeRule = rule;
    _examQuestions = questions;
    _examIndex = 0;
    _examAnswers = {};
    _examReview.clear();
    _focusLost = 0;
    _timeAnomaly = false;
    _examStart = DateTime.now();
    _examRemainingSec = rule.durationMinutes * 60;
    _antiCheat = null; // 不启用防作弊（失焦惩罚/时钟检测）
    _examTimer?.cancel();
    _examTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeRule == null) return; // 已交卷，停止计时
      _examRemainingSec--;
      if (_examRemainingSec <= 0) {
        _autoSubmit(reason: '时间到');
        return;
      }
      notifyListeners();
    });
    WindowService.enterExamMode();
    notifyListeners();
  }

  void setExamAnswer(String qid, String ans) {
    _examAnswers[qid] = ans;
    notifyListeners();
  }

  void gotoExamIndex(int i) {
    if (_activeRule == null) return;
    if (!_activeRule!.allowReviewBack && i < _examIndex) return;
    _examIndex = i;
    notifyListeners();
  }

  void reportFocusLost() {
    _antiCheat?.onFocusLostEvent();
  }

  void reportFocusGained() {
    _antiCheat?.onFocusGained();
  }

  Future<ExamResult> submitExam() => _autoSubmit(reason: '手动交卷');

  bool _submitting = false;
  Future<ExamResult> _autoSubmit({required String reason}) async {
    if (_submitting || _activeRule == null) {
      throw StateError('无进行中的考试或正在交卷');
    }
    _submitting = true;
    _examTimer?.cancel();
    final rule = _activeRule!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final startedAt = _examStart!.millisecondsSinceEpoch;
    final resultId = CryptoService.generateId();

    final answers = <AnswerRecord>[];
    var correct = 0;
    var objectiveScore = 0;
    var subjectiveTotal = 0;
    var hasEssay = false;
    for (final q in _examQuestions) {
      final ua = _examAnswers[q.id] ?? '';
      if (q.type == QuestionType.essay) {
        // 主观题：不自动判分，留待考后人工评卷
        hasEssay = true;
        subjectiveTotal += rule.scorePerQuestion;
        answers.add(AnswerRecord(
            questionId: q.id,
            userAnswer: ua,
            correct: false,
            usedSeconds: 0,
            graded: false));
      } else {
        final ok = Grader.judge(q, ua);
        if (ok) {
          correct++;
          objectiveScore += rule.scorePerQuestion;
        }
        answers.add(AnswerRecord(
            questionId: q.id, userAnswer: ua, correct: ok, usedSeconds: 0));
        if (ok) {
          await _db.recordCorrect(q.id, now);
        } else {
          await _db.recordWrong(q.id, now,
              sourceSessionId: resultId,
              sourceSessionType: 'exam',
              sourceSessionName: rule.name);
        }
      }
    }
    final objectiveCount =
        _examQuestions.where((q) => q.type != QuestionType.essay).length;
    final wrong = objectiveCount - correct;
    final score = objectiveScore; // 主观题分数考后人工补

    final result = ExamResult(
      id: resultId,
      ruleId: rule.id,
      ruleName: rule.name,
      questionIds: _examQuestions.map((q) => q.id).toList(),
      answers: answers,
      startedAt: startedAt,
      submittedAt: now,
      score: score,
      totalScore: rule.totalScore,
      correctCount: correct,
      wrongCount: wrong,
      focusLostCount: _focusLost,
      timeAnomaly: _timeAnomaly,
      autoSubmitted: reason != '手动交卷',
      objectiveScore: objectiveScore,
      subjectiveScore: 0,
      subjectiveTotal: subjectiveTotal,
      graded: !hasEssay,
      passed: rule.totalScore > 0 &&
          score >= (rule.passRate * rule.totalScore).round(),
    );
    await _db.saveExamResult(result);
    WindowService.exitExamMode();
    _activeRule = null;
    _examQuestions = [];
    _examAnswers = {};
    _antiCheat?.dispose();
    _antiCheat = null;
    _submitting = false;
    await loadRulesAndResults();
    notifyListeners();
    return result;
  }

  /// 考后人工评卷：更新主观题分数并重算总分/已评/通过状态。
  Future<void> gradeExam(ExamResult result, Map<String, int> essayScores,
      {double passRate = 0.6}) async {
    var subjectiveScore = 0;
    final updatedAnswers = result.answers.map((a) {
      final sc = essayScores[a.questionId];
      if (sc != null) {
        subjectiveScore += sc;
        return a.copyWith(score: sc, graded: true);
      }
      return a;
    }).toList();
    final allGraded = updatedAnswers.every((a) => a.graded);
    final newScore = result.objectiveScore + subjectiveScore;
    final updated = ExamResult(
      id: result.id,
      ruleId: result.ruleId,
      ruleName: result.ruleName,
      questionIds: result.questionIds,
      answers: updatedAnswers,
      startedAt: result.startedAt,
      submittedAt: result.submittedAt,
      score: newScore,
      totalScore: result.totalScore,
      correctCount: result.correctCount,
      wrongCount: result.wrongCount,
      focusLostCount: result.focusLostCount,
      timeAnomaly: result.timeAnomaly,
      autoSubmitted: result.autoSubmitted,
      objectiveScore: result.objectiveScore,
      subjectiveScore: subjectiveScore,
      subjectiveTotal: result.subjectiveTotal,
      graded: allGraded,
      passed: result.totalScore > 0 &&
          newScore >= (passRate * result.totalScore).round(),
    );
    await _db.saveExamResult(updated);
    await loadRulesAndResults();
  }

  // ============ 错题本 ============
  Future<List<WrongQuestion>> wrongList() => _db.allWrong();
  Future<void> clearWrong(String qid) async {
    await _db.clearWrong(qid);
    notifyListeners();
  }

  Future<void> setMastery(String qid, int level) async {
    await _db.setMastery(qid, level);
    notifyListeners();
  }

  Future<void> setWrongGroup(String qid, String? group) async {
    await _db.setWrongGroup(qid, group);
    notifyListeners();
  }

  Future<List<WrongGroup>> wrongGroups() => _db.allWrongGroups();

  Future<void> saveWrongGroup(WrongGroup g) async {
    await _db.saveWrongGroup(g);
    notifyListeners();
  }

  Future<void> deleteWrongGroup(String id) async {
    await _db.deleteWrongGroup(id);
    notifyListeners();
  }

  @override
  void dispose() {
    _examTimer?.cancel();
    _antiCheat?.dispose();
    super.dispose();
  }
}
