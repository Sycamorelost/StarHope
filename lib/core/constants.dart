/// StarHope 全局常量 —— 核心层（平台无关）
class AppConstants {
  AppConstants._();

  static const String appName = 'StarHope';
  static const String poweredBy = '© Developed and powered by SycamoreLost';

  /// .starhope 文件魔数与版本
  static const String magic = 'STARHOPE';
  static const int formatVersion = 1;

  /// PBKDF2 参数（≥100,000 次迭代）
  static const int pbkdf2Iterations = 120000;
  static const int pbkdf2KeyBits = 256; // AES-256
  static const int saltBytes = 16;
  static const int ivBytes = 12; // GCM 标准 96-bit

  /// 考试防作弊
  static const int examFocusGraceSeconds = 3; // 短暂失焦容忍
  static const int examMaxAwaySeconds = 30; // 离场超时自动交卷
  static const int examClockDriftToleranceMs = 5000;
}

/// 题目类型
enum QuestionType {
  single('单选'),
  multiple('多选'),
  fill('填空'),
  judge('判断'),
  undefined('不定项'),
  essay('主观题');

  final String label;
  const QuestionType(this.label);

  static QuestionType fromString(String? s) {
    switch (s) {
      case 'single':
        return QuestionType.single;
      case 'multiple':
        return QuestionType.multiple;
      case 'fill':
        return QuestionType.fill;
      case 'judge':
        return QuestionType.judge;
      case 'undefined':
        return QuestionType.undefined;
      case 'essay':
        return QuestionType.essay;
      default:
        return QuestionType.single;
    }
  }
}

/// .starhope 内容类型
enum ShareContentType {
  questionBank,
  readingMaterial,
  fullBackup,
  notes,
  exam,
  practiceRecord,
  examResultRecord,
}

extension ShareContentTypeX on ShareContentType {
  String get name {
    switch (this) {
      case ShareContentType.questionBank:
        return 'question_bank';
      case ShareContentType.readingMaterial:
        return 'reading_material';
      case ShareContentType.fullBackup:
        return 'full_backup';
      case ShareContentType.notes:
        return 'notes';
      case ShareContentType.exam:
        return 'exam';
      case ShareContentType.practiceRecord:
        return 'practice_record';
      case ShareContentType.examResultRecord:
        return 'exam_result_record';
    }
  }

  static ShareContentType fromName(String? s) {
    switch (s) {
      case 'reading_material':
        return ShareContentType.readingMaterial;
      case 'full_backup':
        return ShareContentType.fullBackup;
      case 'notes':
        return ShareContentType.notes;
      case 'exam':
        return ShareContentType.exam;
      case 'practice_record':
        return ShareContentType.practiceRecord;
      case 'exam_result_record':
        return ShareContentType.examResultRecord;
      default:
        return ShareContentType.questionBank;
    }
  }
}
