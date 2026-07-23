import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/plugin_format.dart';
import '../services/plugin/plugin_service.dart';

/// 插件状态 Provider：插件列表 + 安装/卸载/启用/参数/导出。
class PluginProvider extends ChangeNotifier {
  final PluginService _svc = PluginService();
  List<Map<String, Object?>> _plugins = const [];
  bool _loading = false;
  // 图标字节缓存：避免工具箱每次 rebuild 都重新读盘（icon.png）。
  final Map<String, Uint8List?> _iconCache = {};

  List<Map<String, Object?>> get plugins => _plugins;
  bool get loading => _loading;

  /// 首次加载：扫描对账 + 读列表。
  Future<void> load() async {
    _loading = true;
    _iconCache.clear();
    notifyListeners();
    try {
      await _svc.scanAndSync();
      _plugins = await _svc.loadAll();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String> install(String packPath) async {
    final id = await _svc.install(packPath);
    await load();
    return id;
  }

  Future<void> uninstall(String id) async {
    await _svc.uninstall(id);
    await load();
  }

  Future<void> setEnabled(String id, bool v) async {
    await _svc.setEnabled(id, v);
    _plugins = await _svc.loadAll();
    notifyListeners();
  }

  Future<void> setParams(String id, String paramsJson) async {
    await _svc.setParams(id, paramsJson);
    _plugins = await _svc.loadAll();
    notifyListeners();
  }

  Future<void> exportPlugin(String id, String destPath,
          {PluginAuthor? author}) =>
      _svc.exportPlugin(id, destPath, author: author);

  Future<Uint8List?> iconBytes(String id) async {
    if (_iconCache.containsKey(id)) return _iconCache[id];
    final bytes = await _svc.iconBytes(id);
    _iconCache[id] = bytes;
    return bytes;
  }

  Future<PluginManifest?> manifestOf(String id) => _svc.manifestOf(id);
}
