import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/plugin_format.dart';
import '../../providers/auth_provider.dart';
import '../../providers/plugin_provider.dart';
import '../../services/plugin/plugin_service.dart';
import '../common/glass.dart';

/// 插件工具箱：导入/导出、3 列毛玻璃插件卡（图标/名/作者/版本/开关/设置）、
/// 单击图标看详情、批量管理、文件夹、下载模板与开发规则。
class PluginToolboxPage extends StatefulWidget {
  const PluginToolboxPage({super.key});
  @override
  State<PluginToolboxPage> createState() => _PluginToolboxPageState();
}

class _PluginToolboxPageState extends State<PluginToolboxPage> {
  final Set<String> _selected = {};
  bool _batchMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PluginProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pv = context.watch<PluginProvider>();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(cs),
          if (_batchMode) _batchBar(pv, cs),
          const SizedBox(height: 12),
          Expanded(
            child: pv.loading && pv.plugins.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : pv.plugins.isEmpty
                    ? _empty(cs)
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.7,
                        ),
                        itemCount: pv.plugins.length,
                        itemBuilder: (_, i) => _pluginCard(pv.plugins[i], cs),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(ColorScheme cs) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _import,
          icon: const Icon(Icons.system_update_alt, size: 18),
          label: const Text('导入插件'),
        ),
        OutlinedButton.icon(
          onPressed: _downloadTemplate,
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('下载模板与规则'),
        ),
        OutlinedButton.icon(
          onPressed: _openPluginsFolder,
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: const Text('插件文件夹'),
        ),
        FilterChip(
          label: Text(_batchMode ? '退出批量' : '批量管理'),
          selected: _batchMode,
          onSelected: (v) => setState(() {
            _batchMode = v;
            _selected.clear();
          }),
        ),
      ],
    );
  }

  Widget _batchBar(PluginProvider pv, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Text('已选 ${_selected.length} 项',
              style: const TextStyle(fontSize: 13)),
          const Spacer(),
          TextButton.icon(
              onPressed: _selected.isEmpty ? null : () => _batch(pv, true),
              icon: const Icon(Icons.toggle_on_outlined),
              label: const Text('启用')),
          TextButton.icon(
              onPressed: _selected.isEmpty ? null : () => _batch(pv, false),
              icon: const Icon(Icons.toggle_off_outlined),
              label: const Text('禁用')),
          TextButton.icon(
              onPressed: _selected.isEmpty ? null : () => _batchUninstall(pv),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('卸载', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _empty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension_outlined,
              size: 56, color: cs.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text('还没有插件',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
              '点「导入插件」安装 .starhope-plugin，或「下载模板与规则」自行开发',
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _pluginCard(Map<String, Object?> plugin, ColorScheme cs) {
    final id = plugin['id'] as String;
    final name = plugin['display_name'] as String? ?? id;
    final author = plugin['author'] as String? ?? '匿名';
    final version = plugin['version'] as String? ?? '';
    final desc = plugin['description'] as String? ?? '';
    final enabled = (plugin['enabled'] as int?) == 1;
    final selected = _selected.contains(id);
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左：图标（单击看详情）+ 左下版本
              GestureDetector(
                onTap: () => _showDetail(plugin),
                child: Column(
                  children: [
                    _icon(id, cs),
                    const SizedBox(height: 6),
                    Text('v$version',
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 右：插件名 / 作者 / 描述 + 开关 / 设置 / 菜单
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 18),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'export', child: Text('导出')),
                            PopupMenuItem(
                                value: 'uninstall', child: Text('卸载')),
                          ],
                          onSelected: (v) => v == 'export'
                              ? _export(plugin)
                              : _uninstall(plugin),
                        ),
                      ],
                    ),
                    Text(author,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (desc.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(desc,
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    const Spacer(),
                    Row(
                      children: [
                        SizedBox(
                          height: 28,
                          child: Switch(
                            value: enabled,
                            onChanged: (v) => context
                                .read<PluginProvider>()
                                .setEnabled(id, v),
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _showParams(plugin),
                          icon: const Icon(Icons.settings_outlined, size: 16),
                          label:
                              const Text('设置', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_batchMode)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() {
                  if (selected) {
                    _selected.remove(id);
                  } else {
                    _selected.add(id);
                  }
                }),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _icon(String id, ColorScheme cs) {
    return FutureBuilder<Uint8List?>(
      future: context.read<PluginProvider>().iconBytes(id),
      builder: (_, snap) {
        if (snap.data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(snap.data!,
                width: 46, height: 46, fit: BoxFit.cover),
          );
        }
        return Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: cs.primaryContainer,
          ),
          child: Icon(Icons.extension, color: cs.onPrimaryContainer),
        );
      },
    );
  }

  // ============ 详情弹窗（单击图标）============
  Future<void> _showDetail(Map<String, Object?> plugin) async {
    final id = plugin['id'] as String;
    final cs = Theme.of(context).colorScheme;
    final manifest = await context.read<PluginProvider>().manifestOf(id);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            _icon(id, cs),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plugin['display_name'] as String? ?? id,
                      style: const TextStyle(fontSize: 18)),
                  Text('v${plugin['version'] ?? ''}',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('作者', plugin['author'] as String? ?? '匿名'),
              _kv('专有名 (ID)', id),
              if ((plugin['description'] as String?)?.isNotEmpty ?? false)
                _kv('描述', plugin['description'] as String),
              _kv('权限',
                  '${(manifest?.permissions ?? const []).join(', ')}（注：阶段 2 不执行脚本）'),
              if (manifest != null && manifest.extensions.isNotEmpty)
                _kv('扩展点',
                    manifest.extensions.map((e) => e['type']).join(', ')),
              _kv('签名', manifest?.author?.signed == true ? '已署名' : '未署名'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 84,
                child: Text(k,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );

  // ============ 参数设置（进入设置）============
  Future<void> _showParams(Map<String, Object?> plugin) async {
    final id = plugin['id'] as String;
    final pv = context.read<PluginProvider>();
    final manifest = await pv.manifestOf(id);
    final schema = manifest?.paramsSchema ?? <String, dynamic>{};
    final cur = plugin['params_json'] as String?;
    final values = cur == null
        ? <String, dynamic>{}
        : (jsonDecode(cur) as Map<String, dynamic>);
    final ctrls = <String, TextEditingController>{};
    schema.forEach((key, def) {
      final m = def is Map<String, dynamic> ? def : <String, dynamic>{};
      final init = values[key] ?? m['default'] ?? '';
      ctrls[key] = TextEditingController(text: '$init');
    });
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${plugin['display_name']} · 参数设置'),
        content: SizedBox(
          width: 360,
          child: schema.isEmpty
              ? const Text('该插件无可配置参数（参数界面将由插件自身在阶段 3 提供）')
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final entry in schema.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            controller: ctrls[entry.key],
                            obscureText:
                                (entry.value is Map && entry.value['secret'] == true) ||
                                    (entry.value is Map &&
                                        entry.value['type'] == 'secret'),
                            decoration: InputDecoration(
                              labelText: (entry.value is Map
                                      ? entry.value['label']
                                      : null) as String? ??
                                  entry.key,
                              border: const OutlineInputBorder(),
                            ),
                          ),
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
              final out = <String, dynamic>{};
              schema.forEach((key, def) {
                final m = def is Map<String, dynamic> ? def : <String, dynamic>{};
                final v = ctrls[key]!.text;
                if (m['type'] == 'integer') {
                  out[key] = int.tryParse(v) ?? v;
                } else if (m['type'] == 'number') {
                  out[key] = double.tryParse(v) ?? v;
                } else {
                  out[key] = v;
                }
              });
              await pv.setParams(id, jsonEncode(out));
              if (ctx.mounted) Navigator.pop(ctx);
              _snack('参数已保存');
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    for (final c in ctrls.values) {
      c.dispose();
    }
  }

  // ============ 导入 ============
  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['starhope-plugin'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    if (!mounted) return;
    try {
      final pv = context.read<PluginProvider>();
      final id = await pv.install(path);
      _snack('已导入插件：$id');
    } catch (e) {
      _snack('导入失败：$e');
    }
  }

  // ============ 导出（含署名选择）============
  Future<void> _export(Map<String, Object?> plugin) async {
    final id = plugin['id'] as String;
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '导出插件',
      fileName: '$id.starhope-plugin',
    );
    if (savePath == null) return;
    final author = await _askAuthor();
    if (!mounted) return;
    try {
      await context.read<PluginProvider>().exportPlugin(id, savePath,
          author: author);
      _snack('已导出：$savePath');
    } catch (e) {
      _snack('导出失败：$e');
    }
  }

  /// 询问是否署名（绑定当前登录用户信息）。
  Future<PluginAuthor?> _askAuthor() async {
    final user = context.read<AuthProvider>().user;
    return showDialog<PluginAuthor>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('作者署名'),
        content: Text(user == null
            ? '是否将作者信息绑定到插件包？'
            : '将绑定：${user.nickname} (@${user.account})'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('不署名')),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx,
                PluginAuthor(
                  nickname: user?.nickname,
                  account: user?.account,
                  github: user?.github,
                  signed: true,
                )),
            child: const Text('署名并导出'),
          ),
        ],
      ),
    );
  }

  // ============ 卸载 ============
  Future<void> _uninstall(Map<String, Object?> plugin) async {
    final id = plugin['id'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('卸载插件'),
        content: Text('确认卸载「${plugin['display_name']}」？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('卸载')),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    final pv = context.read<PluginProvider>();
    await pv.uninstall(id);
    _selected.remove(id);
    _snack('已卸载');
  }

  // ============ 批量 ============
  Future<void> _batch(PluginProvider pv, bool enabled) async {
    for (final id in _selected.toList()) {
      await pv.setEnabled(id, enabled);
    }
    _snack(enabled ? '已批量启用' : '已批量禁用');
  }

  Future<void> _batchUninstall(PluginProvider pv) async {
    for (final id in _selected.toList()) {
      await pv.uninstall(id);
    }
    _selected.clear();
    setState(() {});
    _snack('已批量卸载');
  }

  // ============ 插件文件夹 ============
  Future<void> _openPluginsFolder() async {
    try {
      final dir = await PluginService().pluginsDir();
      await Directory(dir.path).create(recursive: true);
      await Process.run('explorer', [dir.path]);
    } catch (e) {
      _snack('无法打开：$e');
    }
  }

  // ============ 下载模板与规则 ============
  Future<void> _downloadTemplate() async {
    final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择模板与规则的保存位置');
    if (dir == null) return;
    try {
      const manifest = PluginManifest(
        app: 'StarHope',
        id: 'shp.you.hello',
        name: 'Hello 示例插件',
        version: '0.1.0',
        description: 'StarHope 插件开发模板——参考配套的「插件开发规则.md」',
        entry: 'main.js',
        permissions: ['log'],
        author: PluginAuthor(signed: false),
        extensions: [
          {'type': 'tool_page', 'id': 'main', 'title': 'Hello', 'icon': 'extension'}
        ],
        paramsSchema: {
          'who': {'type': 'string', 'label': '打招呼对象', 'default': '世界'}
        },
      );
      final mainJs = Uint8List.fromList(utf8.encode(
          '// Hello 插件入口（阶段 3 由 JS 引擎执行，阶段 2 仅存储）\n'
          '// starhope.log("Hello, " + starhope.params.who);\n'));
      await PluginFile.write(
        path: p.join(dir, 'hello-plugin.starhope-plugin'),
        manifest: manifest,
        files: {'main.js': mainJs},
      );
      await File(p.join(dir, '插件开发规则.md')).writeAsString(_kRules);
      _snack('模板与规则已保存到所选目录');
    } catch (e) {
      _snack('保存失败：$e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: Durations.short2));
  }
}

/// 插件开发规则（随模板下载）。
const _kRules = '''# StarHope 插件开发规则

## 1. 包格式（.starhope-plugin，ZIP）
- `manifest.json` —— 元数据 + 扩展点 + 参数 schema + 权限 + 署名 + 文件清单
- `main.js` —— 入口脚本（阶段 3 由 QuickJS 执行）
- `icon.png` —— 可选图标（46×46 附近）
- `assets/...` —— 可选资源

## 2. 严格署名规范
- `app` 必须为 `"StarHope"`（标识归属本应用，导入时校验）。
- `id` 必须以 `shp.` 开头，形如 `shp.<作者>.<名>`（插件专有名，绑定本应用流通，防泛滥）。
- 作者可选担署名：导出时选择署名则把昵称/账号/github 绑定进 `author`，`signed=true`。

## 3. manifest.json 字段
```json
{
  "app": "StarHope",
  "id": "shp.you.hello",
  "name": "显示名",
  "version": "0.1.0",
  "description": "...",
  "entry": "main.js",
  "permissions": ["log", "storage", "http"],
  "extensions": [ { "type": "tool_page", "id": "main", "title": "Hello", "icon": "extension" } ],
  "params_schema": { "who": { "type": "string", "label": "对象", "default": "世界" } }
}
```

## 4. 防伪
- 每个文件记录 SHA-256，导入时逐一校验；篡改即拒。

## 5. 开发流程
- 自研插件：先在「插件文件夹」放好 manifest.json + main.js（或用此模板）→
  点「导入插件」选中打包好的 .starhope-plugin 安装 → 在软件内「导出」分发。
- 阶段 2：插件可安装/启用/禁用/配置参数，但不执行脚本（main.js 暂存）。
- 阶段 3：接入 JS 引擎，tool_page / command 等扩展点真正运行；插件可经 `http` 权限联网。
''';
