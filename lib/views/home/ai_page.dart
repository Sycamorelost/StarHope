import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../providers/ai_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/file_storage_service.dart';
import '../common/glass.dart';
import '../common/theme.dart';

/// 默认系统提示词（新建智能体时预填，用户可改）
const _kDefaultSystemPrompt =
    '我是你的专属助手，可以回答你简单的问题，帮你处理文档等~\n'
    '你的能力包括：解答学习疑问、处理文档，以及题库支持的文档格式转换'
    '（JSON / CSV / Excel / HTML / Markdown / TXT 之间互转，'
    '遵循 StarHope 题目规范：字段 type、stem、options、answer、'
    'explanation、tags、difficulty）。转换时严格保留题目语义，'
    'options 为数组，多选答案为逗号分隔的索引，填空答案以 || 分隔多空。';

class AIPage extends StatefulWidget {
  const AIPage({super.key});
  @override
  State<AIPage> createState() => _AIPageState();
}

class _AIPageState extends State<AIPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();
  AIAgent? _selectedAgent;

  @override
  void initState() {
    super.initState();
    _inputFocus.onKeyEvent = _onInputKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ai = context.read<AIProvider>();
      final auth = context.read<AuthProvider>();
      if (auth.masterKey != null) ai.injectMasterKey(auth.masterKey!);
      ai.load();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// 回车发送（受 enterToSend 偏好控制；Shift+Enter 仍换行）。
  KeyEventResult _onInputKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey != LogicalKeyboardKey.enter) return KeyEventResult.ignored;
    if (!context.read<ThemeProvider>().enterToSend) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    _send(context.read<AIProvider>());
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AIProvider>();
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 1100;

    if (ai.services.isEmpty) {
      return Scaffold(
        body: Center(
          child: EmptyState(
            icon: Icons.cloud_off_outlined,
            title: '尚未配置 AI 服务',
            subtitle: '先添加 OpenAI 兼容接口或本地 Ollama，再创建智能体。\nAPI 密钥经 AES-GCM 加密存储。',
            action: FilledButton.icon(
              onPressed: () => showEditServiceDialog(context, ai, null),
              icon: const Icon(Icons.add),
              label: const Text('添加 AI 服务'),
            ),
          ),
        ),
      );
    }

    if (ai.agents.isEmpty) {
      return Scaffold(
        body: Center(
          child: EmptyState(
            icon: Icons.smart_toy_outlined,
            title: '尚未创建智能体',
            subtitle: '智能体绑定一个 AI 服务，可自定义系统提示词、模型与采样参数。\n对话时选择智能体即可。',
            action: FilledButton.icon(
              onPressed: () => showEditAgentDialog(context, ai, null),
              icon: const Icon(Icons.add),
              label: const Text('新建智能体'),
            ),
          ),
        ),
      );
    }

    _selectedAgent ??= ai.agents.first;
    if (!ai.agents.contains(_selectedAgent)) {
      _selectedAgent = ai.agents.first;
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (isWide)
              SizedBox(
                width: 280,
                child: _sidebar(context, ai),
              ),
            Expanded(child: _chatArea(context, ai)),
          ],
        ),
      ),
    );
  }

  Widget _sidebar(BuildContext context, AIProvider ai) {
    return GlassCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<AIAgent>(
                  value: _selectedAgent,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: ai.agents
                      .map((a) => DropdownMenuItem(
                            value: a,
                            child: Row(
                              children: [
                                avatarCircle(a.avatarPath, 12),
                                const SizedBox(width: 6),
                                Expanded(
                                    child: Text(a.name,
                                        overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (a) {
                    if (a != null) {
                      ai.selectAgent(a);
                      setState(() => _selectedAgent = a);
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.people_outline),
                tooltip: '管理智能体',
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AgentManagementPage())),
              ),
              IconButton(
                icon: const Icon(Icons.cloud_outlined),
                tooltip: '管理服务',
                onPressed: () => _manageServices(context, ai),
              ),
            ],
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add_comment_outlined),
            title: const Text('新对话'),
            onTap: () {
              ai.startNew();
              setState(() {});
            },
          ),
          Expanded(
            child: ListView.builder(
              itemCount: ai.conversations.length,
              itemBuilder: (_, i) {
                final c = ai.conversations[i];
                final active = ai.current?.id == c.id;
                return ListTile(
                  selected: active,
                  dense: true,
                  title: Text(c.title, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_formatTime(c.updatedAt),
                      style: const TextStyle(fontSize: 11)),
                  onTap: () => ai.openConversation(c.id),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => ai.deleteConversation(c.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatArea(BuildContext context, AIProvider ai) {
    return GlassCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          _chatHeader(context, ai),
          Expanded(
            child: ai.current == null && ai.messages.isEmpty
                ? const Center(child: Text('开始一个新的对话'))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(8),
                    itemCount: ai.messages.length + (ai.streaming ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == ai.messages.length && ai.streaming) {
                        return _bubble(context, 'assistant', ai.streamingText,
                            streaming: true, agent: _selectedAgent);
                      }
                      final m = ai.messages[i];
                      return _bubble(context, m.role, m.content,
                          agent: _selectedAgent, attachments: m.attachments);
                    },
                  ),
          ),
          const Divider(height: 1),
          _inputArea(context, ai),
        ],
      ),
    );
  }

  /// 顶部当前智能体条（宽窄屏均可切换）
  Widget _chatHeader(BuildContext context, AIProvider ai) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          avatarCircle(_selectedAgent?.avatarPath, 12),
          const SizedBox(width: 6),
          Expanded(
            child: PopupMenuButton<AIAgent>(
              tooltip: '切换智能体',
              child: Text(
                  _selectedAgent?.name ?? '选择智能体',
                  overflow: TextOverflow.ellipsis),
              itemBuilder: (_) => ai.agents
                  .map((a) => PopupMenuItem(
                        value: a,
                        child: Row(children: [
                          avatarCircle(a.avatarPath, 12),
                          const SizedBox(width: 6),
                          Expanded(child: Text(a.name)),
                        ]),
                      ))
                  .toList(),
              onSelected: (a) {
                ai.selectAgent(a);
                setState(() => _selectedAgent = a);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑当前智能体',
            onPressed: _selectedAgent == null
                ? null
                : () =>
                    showEditAgentDialog(context, ai, _selectedAgent),
          ),
        ],
      ),
    );
  }

  Widget _inputArea(BuildContext context, AIProvider ai) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ai.pendingAttachments.isNotEmpty)
            SizedBox(
              height: 58,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final a in ai.pendingAttachments)
                    _pendingChip(context, ai, a),
                ],
              ),
            ),
          Row(
            children: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.attach_file),
                tooltip: '添加附件',
                onSelected: (v) =>
                    v == 'image' ? _pickImage(ai) : _pickFile(ai),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'image', child: Text('图片（识图）')),
                  PopupMenuItem(
                      value: 'file', child: Text('文件（文本上下文）')),
                ],
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: context.watch<ThemeProvider>().enterToSend
                        ? '输入消息…（Enter 发送，Shift+Enter 换行）'
                        : '输入消息…',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.swap_horiz),
                      tooltip: '文档格式转换',
                      onPressed: () => _insertContext(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: ai.streaming ? null : () => _send(ai),
                child: const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pendingChip(BuildContext context, AIProvider ai, AttachmentMeta a) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 6),
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: cs.surfaceContainerHighest,
            ),
            clipBehavior: Clip.antiAlias,
            child: (a.isImage && File(a.storedPath).existsSync())
                ? Image.file(File(a.storedPath), fit: BoxFit.cover)
                : Icon(Icons.insert_drive_file_outlined,
                    size: 20, color: cs.onSurfaceVariant),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: () => ai.removeAttachment(a.id),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                    color: cs.error, shape: BoxShape.circle),
                child: Icon(Icons.close, size: 12, color: cs.onError),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, String role, String content,
      {bool streaming = false,
      AIAgent? agent,
      List<AttachmentMeta> attachments = const []}) {
    final isUser = role == 'user';
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.7),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser
              ? cs.primary
              : cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    avatarCircle(agent?.avatarPath, 8),
                    const SizedBox(width: 4),
                    Text(agent?.name ?? 'AI',
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            if (isUser && attachments.any((a) => a.isImage))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in attachments.where((a) => a.isImage))
                      _imageThumb(a, cs),
                  ],
                ),
              ),
            MarkdownBody(
              data: content.isEmpty && streaming ? '…' : content,
              selectable: !streaming,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                      p: TextStyle(color: isUser ? cs.onPrimary : null)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageThumb(AttachmentMeta a, ColorScheme cs) {
    if (!File(a.storedPath).existsSync()) {
      return Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.broken_image_outlined),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(File(a.storedPath),
          width: 120, height: 120, fit: BoxFit.cover),
    );
  }

  Future<void> _pickImage(AIProvider ai) async {
    final existing = ai.pendingAttachments.where((a) => a.isImage).length;
    if (existing >= 6) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('单次最多 6 张图片')));
      return;
    }
    final r = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: true);
    if (r == null) return;
    for (final f in r.files) {
      if (f.path == null) continue;
      if (f.size > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${f.name} 超过 5MB，已跳过')));
        }
        continue;
      }
      await ai.addAttachment(path: f.path!, fileName: f.name);
    }
  }

  Future<void> _pickFile(AIProvider ai) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md', 'csv', 'json', 'html', 'log'],
      allowMultiple: true,
    );
    if (r == null) return;
    for (final f in r.files) {
      if (f.path == null) continue;
      await ai.addAttachment(path: f.path!, fileName: f.name);
    }
  }

  Future<void> _send(AIProvider ai) async {
    final agent = _selectedAgent;
    if (_input.text.trim().isEmpty || agent == null) return;
    final text = _input.text;
    _input.clear();
    try {
      await ai.send(userInput: text, agent: agent);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      }
    });
  }

  /// 插入"文档格式转换"提示词模板
  void _insertContext(BuildContext context) {
    setState(() {
      _input.text =
          '请帮我把以下题库内容转换为【目标格式，如 JSON/CSV/Excel/HTML/Markdown】：\n\n'
          '<在此粘贴题目内容>\n\n'
          '要求：保留题型、题干、选项、答案、解析、标签与难度字段。';
      _input.selection =
          TextSelection.fromPosition(const TextPosition(offset: 0));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已插入格式转换模板，请补充目标格式与题目内容')),
    );
  }

  String _formatTime(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms).toString().substring(0, 16);

  void _manageServices(BuildContext context, AIProvider ai) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('AI 服务管理')),
            for (final s in ai.services)
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: Text(s.name),
                subtitle: Text('${s.type.name} · ${s.model}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () {
                          Navigator.pop(ctx);
                          showEditServiceDialog(context, ai, s);
                        }),
                    IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => ai.deleteService(s.id)),
                  ],
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('添加服务'),
              onTap: () {
                Navigator.pop(ctx);
                showEditServiceDialog(context, ai, null);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 智能体管理子页
class AgentManagementPage extends StatelessWidget {
  const AgentManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AIProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('智能体管理')),
      body: FrostedBackground(
        child: ai.agents.isEmpty
          ? Center(
              child: EmptyState(
                icon: Icons.smart_toy_outlined,
                title: '尚未创建智能体',
                subtitle: '智能体绑定一个 AI 服务，可自定义系统提示词、模型与采样参数。',
                action: FilledButton.icon(
                  onPressed: () => showEditAgentDialog(context, ai, null),
                  icon: const Icon(Icons.add),
                  label: const Text('新建智能体'),
                ),
              ),
            )
          : ListView.builder(
              itemCount: ai.agents.length,
              itemBuilder: (_, i) {
                final a = ai.agents[i];
                final svc = ai.services.where((s) => s.id == a.serviceId).toList();
                final subtitle = svc.isEmpty
                    ? '（关联服务已删除）'
                    : '${svc.first.name} · ${a.model ?? svc.first.model}';
                return ListTile(
                  leading: avatarCircle(a.avatarPath, 20),
                  title: Text(a.name),
                  subtitle: Text(subtitle),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () =>
                            showEditAgentDialog(context, ai, a),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => ai.deleteAgent(a.id),
                      ),
                    ],
                  ),
                );
              },
            ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showEditAgentDialog(context, ai, null),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 智能体头像（本地文件优先，缺失回退机器人图标）
Widget avatarCircle(String? path, double radius) {
  if (path != null && File(path).existsSync()) {
    return CircleAvatar(
        radius: radius, backgroundImage: FileImage(File(path)));
  }
  return CircleAvatar(
    radius: radius,
    backgroundColor: Colors.transparent,
    child: Icon(Icons.smart_toy, size: radius * 1.3),
  );
}

/// 智能体编辑/新建弹窗
void showEditAgentDialog(BuildContext context, AIProvider ai, AIAgent? existing) {
  final name = TextEditingController(text: existing?.name ?? '');
  final systemPrompt =
      TextEditingController(text: existing?.systemPrompt ?? _kDefaultSystemPrompt);
  final model = TextEditingController(text: existing?.model ?? '');
  final maxTokens =
      TextEditingController(text: existing?.maxTokens?.toString() ?? '');
  String serviceId = existing?.serviceId ??
      (ai.services.isNotEmpty ? ai.services.first.id : '');
  String? avatarPath = existing?.avatarPath;
  bool useTemp = existing?.temperature != null;
  double temp = existing?.temperature ?? 0.7;
  bool useTopP = existing?.topP != null;
  double topP = existing?.topP ?? 0.9;
  bool useMaxTokens = existing?.maxTokens != null;

  showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(existing == null ? '新建智能体' : '编辑智能体'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final r = await FilePicker.platform
                            .pickFiles(type: FileType.image);
                        if (r != null && r.files.single.path != null) {
                          try {
                            final p = await FileStorageService.saveAvatar(
                                r.files.single.path!);
                            set(() => avatarPath = p);
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx)
                                  .showSnackBar(SnackBar(content: Text('$e')));
                            }
                          }
                        }
                      },
                      child: avatarCircle(avatarPath, 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                          controller: name,
                          decoration: const InputDecoration(labelText: '名称')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: serviceId.isEmpty ? null : serviceId,
                  decoration: const InputDecoration(labelText: 'AI 服务'),
                  items: ai.services
                      .map((s) => DropdownMenuItem(
                            value: s.id,
                            child: Text('${s.name} (${s.model})',
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => set(() => serviceId = v ?? ''),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: model,
                  decoration: const InputDecoration(
                      labelText: '模型', hintText: '留空则用服务默认模型'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: systemPrompt,
                  maxLines: 5,
                  decoration: const InputDecoration(
                      labelText: '系统提示词', alignLabelWithHint: true),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  dense: true,
                  value: useTemp,
                  onChanged: (v) => set(() => useTemp = v),
                  title: const Text('Temperature'),
                ),
                if (useTemp)
                  Slider(
                      value: temp,
                      min: 0,
                      max: 2,
                      divisions: 20,
                      label: temp.toStringAsFixed(2),
                      onChanged: (v) => set(() => temp = v)),
                SwitchListTile(
                  dense: true,
                  value: useTopP,
                  onChanged: (v) => set(() => useTopP = v),
                  title: const Text('Top P'),
                ),
                if (useTopP)
                  Slider(
                      value: topP,
                      min: 0,
                      max: 1,
                      divisions: 20,
                      label: topP.toStringAsFixed(2),
                      onChanged: (v) => set(() => topP = v)),
                SwitchListTile(
                  dense: true,
                  value: useMaxTokens,
                  onChanged: (v) => set(() => useMaxTokens = v),
                  title: const Text('Max Tokens'),
                ),
                if (useMaxTokens)
                  TextField(
                    controller: maxTokens,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '如 2048'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              if (serviceId.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('请选择 AI 服务')));
                return;
              }
              final agent = AIAgent(
                id: existing?.id ?? '',
                name: name.text.isEmpty ? '智能体' : name.text,
                avatarPath: avatarPath,
                systemPrompt: systemPrompt.text,
                serviceId: serviceId,
                model: model.text.isEmpty ? null : model.text,
                temperature: useTemp ? temp : null,
                topP: useTopP ? topP : null,
                maxTokens: useMaxTokens ? int.tryParse(maxTokens.text) : null,
                createdAt: existing?.createdAt ?? 0,
              );
              await ai.saveAgent(agent);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

/// AI 服务编辑/新建弹窗
void showEditServiceDialog(
    BuildContext context, AIProvider ai, AIServiceConfig? existing) {
  final name = TextEditingController(text: existing?.name ?? '');
  final baseUrl = TextEditingController(text: existing?.baseUrl ?? '');
  final model = TextEditingController(text: existing?.model ?? '');
  final apiKey = TextEditingController();
  AIServiceType type = existing?.type ?? AIServiceType.openai;

  showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(existing == null ? '添加 AI 服务' : '编辑服务'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '名称')),
                const SizedBox(height: 8),
                SegmentedButton<AIServiceType>(
                  segments: const [
                    ButtonSegment(
                        value: AIServiceType.openai,
                        label: Text('OpenAI 兼容')),
                    ButtonSegment(
                        value: AIServiceType.ollama, label: Text('Ollama')),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) => set(() => type = s.first),
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: baseUrl,
                    decoration: InputDecoration(
                        labelText: 'Base URL',
                        hintText: type == AIServiceType.ollama
                            ? 'http://localhost:11434'
                            : 'https://api.openai.com/v1')),
                const SizedBox(height: 8),
                TextField(
                    controller: model,
                    decoration: const InputDecoration(labelText: '模型')),
                const SizedBox(height: 8),
                TextField(
                  controller: apiKey,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: existing?.hasApiKey == true
                        ? '已保存，留空则不修改'
                        : (type == AIServiceType.ollama
                            ? 'Ollama 通常无需'
                            : 'sk-…'),
                  ),
                ),
                const SizedBox(height: 8),
                Text('密钥将以 AES-GCM 加密存储，仅在使用时内存解密。',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final svc = AIServiceConfig(
                id: existing?.id ?? '',
                name: name.text.isEmpty ? 'AI 服务' : name.text,
                type: type,
                baseUrl: baseUrl.text,
                model: model.text,
                apiKeyEncrypted: existing?.apiKeyEncrypted ?? '',
                hasApiKey: existing?.hasApiKey ?? false,
              );
              await ai.saveService(
                  svc, apiKey.text.isEmpty ? null : apiKey.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}
