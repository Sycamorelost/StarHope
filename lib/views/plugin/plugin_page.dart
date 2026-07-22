import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/plugin/plugin_runtime.dart';
import '../../services/plugin/plugin_service.dart';
import '../common/theme.dart';
import '../common/window_title_bar.dart';
import 'widget_view.dart';

/// 插件运行页：加载并执行插件 main.js，渲染其 tool_page（render() 返回的 JSON 树）。
class PluginPage extends StatefulWidget {
  final String id;
  const PluginPage({super.key, required this.id});

  @override
  State<PluginPage> createState() => _PluginPageState();
}

class _PluginPageState extends State<PluginPage> {
  PluginRuntime? _runtime;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    try {
      final svc = PluginService();
      final manifest = await svc.manifestOf(widget.id);
      if (manifest == null) {
        if (mounted) setState(() => _error = '插件清单缺失');
        return;
      }
      final dir = await svc.pluginDir(widget.id);
      final mainFile = File(p.join(dir.path, manifest.entry));
      if (!await mainFile.exists()) {
        if (mounted) setState(() => _error = '入口文件 ${manifest.entry} 缺失');
        return;
      }
      final mainJs = await mainFile.readAsString();
      final rt = await PluginRuntime.load(widget.id, mainJs);
      if (mounted) setState(() => _runtime = rt);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _runtime?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FrostedBackground(
      child: Column(
        children: [
          WindowTitleBar(
            title: _runtime?.title ?? widget.id,
            leading: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 18),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('插件加载失败：$_error',
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center),
                    ),
                  )
                : _runtime == null
                    ? const Center(child: CircularProgressIndicator())
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: PluginWidgetView(runtime: _runtime!),
                      ),
          ),
        ],
      ),
    );
  }
}
