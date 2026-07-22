import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/crypto/crypto_service.dart';
import '../core/models/models.dart';
import 'database/database.dart';

/// 一条对话消息：content 为文本，images 为图片附件（用于多模态识图）。
class ChatMessage {
  final String role; // system / user / assistant
  final String content;
  final List<AttachmentMeta> images;

  const ChatMessage({
    required this.role,
    required this.content,
    this.images = const [],
  });
}

/// 模型参数（覆盖服务默认；null 表示不传，沿用服务端默认）。
class ChatOptions {
  final String? model;
  final double? temperature;
  final double? topP;
  final int? maxTokens;

  const ChatOptions({this.model, this.temperature, this.topP, this.maxTokens});

  /// OpenAI 兼容接口的顶层字段。
  Map<String, dynamic> toOpenAiFields() => {
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (maxTokens != null) 'max_tokens': maxTokens,
      };

  /// Ollama 的 options 对象字段（maxTokens 映射为 num_predict）。
  Map<String, dynamic> toOllamaOptions() => {
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (maxTokens != null) 'num_predict': maxTokens,
      };
}

/// AI 服务（服务层）
///
/// 支持 OpenAI 兼容接口与本地 Ollama。API 密钥经 AES-GCM 加密存储，
/// 密钥派生自主密码；仅在使用时内存解密，用完即焚。
/// 流式对话通过 HTTP Stream 逐块接收，回调打字机式拼接。
/// 支持图片附件多模态（OpenAI vision content array / Ollama images）。
class AIService {
  final AppDatabase _db = AppDatabase.instance;

  /// 加密 API Key（需主密钥）
  String encryptApiKey(String plain, Uint8List masterKey) =>
      CryptoService.encryptString(plain, masterKey);

  /// 解密 API Key
  String? decryptApiKey(AIServiceConfig svc, Uint8List masterKey) {
    if (!svc.hasApiKey || svc.apiKeyEncrypted.isEmpty) return null;
    try {
      return CryptoService.decryptString(svc.apiKeyEncrypted, masterKey);
    } catch (_) {
      return null;
    }
  }

  /// 流式对话。返回助手完整回复文本。
  /// [messages] 携带文本与可选图片附件；[options] 覆盖模型与采样参数。
  /// [onDelta] 实时回调增量片段（打字机效果）。
  Future<String> chatStream({
    required AIServiceConfig svc,
    required Uint8List masterKey,
    required List<ChatMessage> messages,
    ChatOptions options = const ChatOptions(),
    void Function(String delta)? onDelta,
  }) async {
    final apiKey = decryptApiKey(svc, masterKey);
    final model = options.model ?? svc.model;

    if (svc.type == AIServiceType.ollama) {
      return _chatOllama(svc, model, messages, options, onDelta);
    }
    return _chatOpenAI(svc, apiKey ?? '', model, messages, options, onDelta);
  }

  Future<String> _chatOpenAI(
    AIServiceConfig svc,
    String apiKey,
    String model,
    List<ChatMessage> messages,
    ChatOptions options,
    void Function(String delta)? onDelta,
  ) async {
    final url = '${_normalizeBase(svc.baseUrl)}/chat/completions';
    final req = http.Request('POST', Uri.parse(url));
    req.headers['Content-Type'] = 'application/json';
    if (apiKey.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $apiKey';
    }

    final msgsJson = messages.map((m) {
      if (m.images.isEmpty) {
        return {'role': m.role, 'content': m.content};
      }
      // 多模态：content 为数组，文本块在前，图片块在后
      final arr = <Map<String, dynamic>>[];
      if (m.content.isNotEmpty) arr.add({'type': 'text', 'text': m.content});
      for (final img in m.images) {
        final b64 = readImageBase64(img.storedPath);
        if (b64 == null) continue;
        arr.add({
          'type': 'image_url',
          'image_url': {'url': 'data:${img.mimeType};base64,$b64'},
        });
      }
      return {'role': m.role, 'content': arr};
    }).toList();

    req.body = jsonEncode({
      'model': model,
      'stream': true,
      'messages': msgsJson,
      ...options.toOpenAiFields(),
    });

    final client = http.Client();
    final response = await client.send(req);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('AI 服务返回 ${response.statusCode}: $body');
    }

    final sb = StringBuffer();
    final lineBuf = StringBuffer();
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      lineBuf.write(chunk);
      final lines = lineBuf.toString().split('\n');
      lineBuf.clear();
      // 保留最后一个不完整行
      if (!_endsWithNewline(chunk)) lineBuf.write(lines.removeLast());
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]') continue;
        try {
          final obj = jsonDecode(data) as Map<String, dynamic>;
          final delta = obj['choices']?[0]?['delta']?['content'];
          if (delta is String && delta.isNotEmpty) {
            sb.write(delta);
            onDelta?.call(delta);
          }
        } catch (_) {
          // 忽略解析错误，继续
        }
      }
    }
    client.close();
    return sb.toString();
  }

  Future<String> _chatOllama(
    AIServiceConfig svc,
    String model,
    List<ChatMessage> messages,
    ChatOptions options,
    void Function(String delta)? onDelta,
  ) async {
    final url = '${_normalizeBase(svc.baseUrl)}/api/chat';
    final req = http.Request('POST', Uri.parse(url));
    req.headers['Content-Type'] = 'application/json';

    final msgsJson = messages.map((m) {
      final obj = <String, dynamic>{'role': m.role, 'content': m.content};
      if (m.images.isNotEmpty) {
        final imgs = <String>[];
        for (final img in m.images) {
          final b64 = readImageBase64(img.storedPath);
          if (b64 != null) imgs.add(b64);
        }
        if (imgs.isNotEmpty) obj['images'] = imgs;
      }
      return obj;
    }).toList();

    final ollamaOpts = options.toOllamaOptions();
    req.body = jsonEncode({
      'model': model,
      'stream': true,
      'messages': msgsJson,
      if (ollamaOpts.isNotEmpty) 'options': ollamaOpts,
    });

    final client = http.Client();
    final response = await client.send(req);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Ollama 返回 ${response.statusCode}: $body');
    }

    final sb = StringBuffer();
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      // Ollama 每行一个 JSON
      for (final raw in chunk.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        try {
          final obj = jsonDecode(line) as Map<String, dynamic>;
          final delta = obj['message']?['content'];
          if (delta is String && delta.isNotEmpty) {
            sb.write(delta);
            onDelta?.call(delta);
          }
        } catch (_) {
          // 忽略
        }
      }
    }
    client.close();
    return sb.toString();
  }

  String _normalizeBase(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  bool _endsWithNewline(String s) => s.endsWith('\n') || s.endsWith('\r');

  /// 读图片为 base64；文件缺失或读取失败返回 null（该图静默跳过）。
  static String? readImageBase64(String storedPath) {
    try {
      final f = File(storedPath);
      if (!f.existsSync()) return null;
      return base64.encode(f.readAsBytesSync());
    } catch (_) {
      return null;
    }
  }

  /// 将纯文本类附件内容拼入提问文本（二进制附件仅以文件名占位）。
  /// 文本类（text/*、json、csv）读取 UTF-8 内容，超过 50KB 截断。
  static String composeTextWithDocs(
      String userText, List<AttachmentMeta> allAtts) {
    final docs = allAtts.where((a) => !a.isImage).toList();
    if (docs.isEmpty) return userText;
    final sb = StringBuffer(userText);
    for (final d in docs) {
      sb.writeln();
      sb.writeln();
      sb.writeln('[附件: ${d.fileName}]');
      if (_isTextLike(d.mimeType)) {
        try {
          var raw = File(d.storedPath).readAsStringSync();
          if (raw.length > _maxDocTextBytes) {
            raw = '${raw.substring(0, _maxDocTextBytes)}…(已截断)';
          }
          sb.writeln('```');
          sb.writeln(raw);
          sb.writeln('```');
        } catch (_) {
          sb.writeln('（无法读取：编码异常或文件缺失）');
        }
      } else {
        sb.writeln('（二进制附件，仅以文件名作为上下文）');
      }
    }
    return sb.toString();
  }

  static const _textMimePrefixes = [
    'text/',
    'application/json',
    'application/csv',
  ];
  static const int _maxDocTextBytes = 50 * 1024;

  static bool _isTextLike(String mime) =>
      _textMimePrefixes.any((p) => mime.startsWith(p));

  // ============ 配置 CRUD ============
  Future<List<AIServiceConfig>> listServices() => _db.allAIServices();
  Future<void> saveService(AIServiceConfig s) => _db.saveAIService(s);
  Future<void> deleteService(String id) => _db.deleteAIService(id);
}
