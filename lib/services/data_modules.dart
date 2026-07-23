/// 数据模块注册表：备份 / 恢复 / 清空三处共用的**单一数据源**。
///
/// 此前模块清单散落在三处（`_pickBackupModules` 的展示列表、`_factoryReset` 的
/// 模块→表 map、`fullBackup`/`restoreBackup` 的分支），新增模块需改多处且易遗漏。
/// 现统一为本注册表：每个模块描述 [id]、显示名 [label]、清空时影响的数据库表
/// [tables]、备份载荷中的键 [payloadKey]。
///
/// UI 图标由视图层按 [id] 映射，保持本服务层无 Flutter 依赖（分层洁净）。
class DataModule {
  final String id;
  final String label;
  final List<String> tables;
  final String payloadKey;

  const DataModule(this.id, this.label, this.tables, this.payloadKey);

  /// 全部模块（顺序即 UI 展示顺序）。
  static const all = <DataModule>[
    DataModule('questions', '题库题目', ['questions'], 'questions'),
    DataModule('folders', '题库文件夹', ['question_folders'], 'question_folders'),
    DataModule('practices', '练习历史', ['practice_sessions'], 'practice_sessions'),
    DataModule('exam_rules', '考试规则', ['exam_rules'], 'exam_rules'),
    DataModule('exam_results', '考试结果', ['exam_results'], 'exam_results'),
    DataModule('wrong', '错题本', ['wrong_questions'], 'wrong_questions'),
    DataModule('wrong_groups', '错题分组', ['wrong_groups'], 'wrong_groups'),
    DataModule('materials', '阅读资料与笔记', ['reading_materials', 'notes'], 'materials'),
    DataModule('ai_services', 'AI 服务配置（不含密钥）', ['ai_services'], 'ai_services'),
    DataModule('ai_agents', 'AI 智能体', ['ai_agents'], 'ai_agents'),
    DataModule('ai_conversations', 'AI 对话', ['ai_conversations'], 'ai_conversations'),
    DataModule('ai_messages', 'AI 消息', ['ai_messages'], 'ai_messages'),
    DataModule('plugins', '插件（含数据）', ['plugins'], 'plugins'),
  ];

  static DataModule? byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 选中的模块集合 → 需清空的数据库表集合（供 clearAll 与选择性清空/恢复复用）。
  static Set<String> tablesFor(Set<String> modules) {
    final t = <String>{};
    for (final id in modules) {
      t.addAll(byId(id)?.tables ?? const <String>[]);
    }
    return t;
  }

  /// 备份文件中实际存在的模块 id 集合（按 [payloadKey] 探测载荷）。
  /// 供恢复时的模块选择器只展示备份里真正有的模块。
  static Set<String> presentIn(Map<String, dynamic> payload) {
    return {for (final m in all) if (payload.containsKey(m.payloadKey)) m.id};
  }
}
