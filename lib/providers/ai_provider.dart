import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/crypto/crypto_service.dart';
import '../core/models/models.dart';
import '../services/ai_service.dart';
import '../services/database/database.dart';
import '../services/file_storage_service.dart';

/// AI 助手状态 Provider
class AIProvider extends ChangeNotifier {
  final AIService _ai = AIService();
  final AppDatabase _db = AppDatabase.instance;

  List<AIServiceConfig> _services = [];
  List<AIAgent> _agents = [];
  List<AIConversation> _conversations = [];
  List<AIMessage> _messages = [];
  AIConversation? _current;
  AIAgent? _selectedAgent;
  List<AttachmentMeta> _pendingAttachments = [];
  bool _streaming = false;
  String _streamingText = '';

  List<AIServiceConfig> get services => _services;
  List<AIAgent> get agents => _agents;
  List<AIConversation> get conversations => _conversations;
  List<AIMessage> get messages => _messages;
  AIConversation? get current => _current;
  AIAgent? get selectedAgent => _selectedAgent;
  List<AttachmentMeta> get pendingAttachments => _pendingAttachments;
  bool get streaming => _streaming;
  String get streamingText => _streamingText;

  Future<void> load() async {
    _services = await _db.allAIServices();
    _agents = await _db.allAgents();
    _conversations = await _db.allConversations();
    if (_selectedAgent != null && !_agents.contains(_selectedAgent)) {
      _selectedAgent = null;
    }
    _selectedAgent ??= _agents.isNotEmpty ? _agents.first : null;
    notifyListeners();
  }

  // ============ 服务 ============
  Future<void> saveService(AIServiceConfig svc, String? plainKey) async {
    final config = plainKey != null && plainKey.isNotEmpty
        ? AIServiceConfig(
            id: svc.id.isEmpty ? CryptoService.generateId() : svc.id,
            name: svc.name,
            type: svc.type,
            baseUrl: svc.baseUrl,
            model: svc.model,
            apiKeyEncrypted: _ai.encryptApiKey(plainKey, _requireMaster()),
            hasApiKey: true,
          )
        : svc;
    await _db.saveAIService(config);
    await load();
  }

  Future<void> deleteService(String id) async {
    await _db.deleteAIService(id);
    await load();
  }

  // ============ 智能体 ============
  void selectAgent(AIAgent a) {
    _selectedAgent = a;
    notifyListeners();
  }

  Future<void> saveAgent(AIAgent a) async {
    final agent = a.id.isEmpty
        ? AIAgent(
            id: CryptoService.generateId(),
            name: a.name.isEmpty ? '智能体' : a.name,
            avatarPath: a.avatarPath,
            systemPrompt: a.systemPrompt,
            serviceId: a.serviceId,
            model: a.model,
            temperature: a.temperature,
            topP: a.topP,
            maxTokens: a.maxTokens,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          )
        : a;
    await _db.saveAgent(agent);
    _selectedAgent = agent;
    await load();
  }

  Future<void> deleteAgent(String id) async {
    await _db.deleteAgent(id);
    await load();
  }

  // ============ 待发附件 ============
  Future<void> addAttachment({
    required String path,
    required String fileName,
  }) async {
    final meta = await FileStorageService.importAttachment(
      sourcePath: path,
      fileName: fileName,
    );
    _pendingAttachments = [..._pendingAttachments, meta];
    notifyListeners();
  }

  void removeAttachment(String id) {
    final remaining = _pendingAttachments.where((a) => a.id != id).toList();
    if (remaining.length == _pendingAttachments.length) return;
    final removed = _pendingAttachments.firstWhere((a) => a.id == id);
    FileStorageService.deleteAttachment(removed.storedPath);
    _pendingAttachments = remaining;
    notifyListeners();
  }

  // ============ 对话 ============
  Future<void> openConversation(String id) async {
    _current = _conversations.firstWhere((c) => c.id == id);
    _messages = await _db.messagesOf(id);
    _pendingAttachments = [];
    final aid = _current!.agentId;
    if (aid != null) {
      try {
        _selectedAgent = _agents.firstWhere((x) => x.id == aid);
      } catch (_) {
        // agent 已删，保持当前选中
      }
    }
    notifyListeners();
  }

  /// 开始新对话（清空当前）
  void startNew() {
    _current = null;
    _messages = [];
    _pendingAttachments = [];
    notifyListeners();
  }

  Future<AIConversation> newConversation({
    required String serviceId,
    required String title,
    String? agentId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final conv = AIConversation(
      id: CryptoService.generateId(),
      title: title,
      serviceId: serviceId,
      agentId: agentId,
      createdAt: now,
      updatedAt: now,
    );
    await _db.saveConversation(conv);
    _current = conv;
    _messages = [];
    await load();
    return conv;
  }

  Future<void> renameConversation(String id, String title) async {
    final c = _conversations.firstWhere((e) => e.id == id);
    final updated = AIConversation(
      id: c.id,
      title: title,
      serviceId: c.serviceId,
      agentId: c.agentId,
      createdAt: c.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.saveConversation(updated);
    await load();
  }

  Future<void> deleteConversation(String id) async {
    await _db.deleteConversation(id);
    if (_current?.id == id) {
      _current = null;
      _messages = [];
      _pendingAttachments = [];
    }
    await load();
  }

  /// 发送消息并流式接收回复。基于 [agent]（系统提示词/模型/参数）。
  /// 图片附件走多模态，纯文本类附件已拼入提问文本。
  Future<void> send({
    required String userInput,
    required AIAgent agent,
  }) async {
    final svc = _services.firstWhere(
      (s) => s.id == agent.serviceId,
      orElse: () => throw StateError('该智能体关联的 AI 服务已被删除'),
    );

    if (_current == null) {
      await newConversation(
        serviceId: svc.id,
        title: _deriveTitle(userInput),
        agentId: agent.id.isEmpty ? null : agent.id,
      );
    }

    final composedText =
        AIService.composeTextWithDocs(userInput, _pendingAttachments);
    final imageAtts = _pendingAttachments.where((a) => a.isImage).toList();
    final userMsg = AIMessage(
      id: CryptoService.generateId(),
      conversationId: _current!.id,
      role: 'user',
      content: composedText,
      attachments: imageAtts,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.saveMessage(userMsg);
    _messages = [..._messages, userMsg];

    _streaming = true;
    _streamingText = '';
    notifyListeners();

    final history = <ChatMessage>[];
    if (agent.systemPrompt.isNotEmpty) {
      history.add(ChatMessage(role: 'system', content: agent.systemPrompt));
    }
    for (final m in _messages) {
      history.add(ChatMessage(
        role: m.role,
        content: m.content,
        images: m.attachments.where((a) => a.isImage).toList(),
      ));
    }

    final options = ChatOptions(
      model: agent.model,
      temperature: agent.temperature,
      topP: agent.topP,
      maxTokens: agent.maxTokens,
    );

    try {
      final full = await _ai.chatStream(
        svc: svc,
        masterKey: _requireMaster(),
        messages: history,
        options: options,
        onDelta: (d) {
          _streamingText += d;
          notifyListeners();
        },
      );
      final aiMsg = AIMessage(
        id: CryptoService.generateId(),
        conversationId: _current!.id,
        role: 'assistant',
        content: full,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _db.saveMessage(aiMsg);
      _messages = [..._messages, aiMsg];
      _pendingAttachments = [];
    } catch (e) {
      final lower = e.toString().toLowerCase();
      final hint = lower.contains('image') || lower.contains('vision');
      final errMsg = AIMessage(
        id: CryptoService.generateId(),
        conversationId: _current!.id,
        role: 'assistant',
        content: hint ? '⚠️ 请求失败（所选模型可能不支持图像）：$e' : '⚠️ 请求失败：$e',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _db.saveMessage(errMsg);
      _messages = [..._messages, errMsg];
    } finally {
      _streaming = false;
      _streamingText = '';
      if (_current != null) {
        final updated = AIConversation(
          id: _current!.id,
          title: _current!.title,
          serviceId: _current!.serviceId,
          agentId: _current!.agentId,
          createdAt: _current!.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await _db.saveConversation(updated);
        _current = updated;
      }
      await load();
      notifyListeners();
    }
  }

  String _deriveTitle(String s) {
    final t = s.trim().replaceAll('\n', ' ');
    return t.length > 20 ? '${t.substring(0, 20)}…' : t;
  }

  Uint8List _requireMaster() {
    final k = _injectedMasterKey;
    if (k == null) {
      throw StateError('主密钥未就绪，请重新登录');
    }
    return k;
  }

  // 主密钥由 UI 层在登录后注入（来自 AuthProvider.masterKey）
  Uint8List? _injectedMasterKey;
  void injectMasterKey(Uint8List key) => _injectedMasterKey = key;
}
