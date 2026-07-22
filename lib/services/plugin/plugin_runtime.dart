import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:path/path.dart' as p;

import '../storage_config.dart';

/// 插件 JS 运行时（阶段 3）：基于 flutter_js(QuickJS)，注入受限宿主 API
/// `starhope.{log, storage}`，执行 main.js，并暴露 render()/onAction() 给宿主渲染 tool_page。
///
/// storage 同步可读（注入为 JS 全局），写时通过 channel 异步持久化到
/// <dataRoot>/plugins/<id>/storage.json。
class PluginRuntime {
  final String id;
  final JavascriptRuntime _rt;
  final File _storageFile;
  final Map<String, dynamic> _storage;
  void Function()? onRerender;

  PluginRuntime._(this.id, this._rt, this._storageFile, this._storage);

  /// 创建并初始化运行时：读 storage、注入宿主 API、执行 [mainJs]。
  static Future<PluginRuntime> load(String id, String mainJs) async {
    final rt = getJavascriptRuntime();
    final root = await StorageConfig.dataRoot();
    final storageFile = File(p.join(root, 'plugins', id, 'storage.json'));
    Map<String, dynamic> storage = {};
    if (await storageFile.exists()) {
      try {
        storage =
            jsonDecode(await storageFile.readAsString()) as Map<String, dynamic>;
      } catch (_) {}
    }
    final inst = PluginRuntime._(id, rt, storageFile, storage);
    inst._setupHost();
    final res = rt.evaluate(mainJs); // 执行插件脚本（注册 render/onAction 等）
    if (res.isError) {
      rt.dispose();
      throw Exception('脚本执行错误: ${res.stringResult}');
    }
    return inst;
  }

  void _setupHost() {
    _rt.onMessage('StarhopeLog', (args) {
      debugPrint('[plugin:$id] $args');
    });
    _rt.onMessage('Rerender', (_) => onRerender?.call());
    _rt.onMessage('StarhopeStorage', (args) async {
      try {
        final list = args as List;
        _storage[list[0]] = list[1];
        await _storageFile.parent.create(recursive: true);
        await _storageFile
            .writeAsString(const JsonEncoder.withIndent('  ').convert(_storage));
      } catch (e) {
        debugPrint('[plugin:$id] storage persist failed: $e');
      }
    });
    _rt.evaluate(_hostScript());
  }

  /// 注入 starhope 宿主 API（storage 同步可读 + 写时持久化 + log）。
  String _hostScript() => '''
    var starhope = {
      _storage: ${jsonEncode(_storage)},
      log: function(){ sendMessage('StarhopeLog', JSON.stringify(Array.prototype.slice.call(arguments))); },
    };
    starhope.storage = {
      get: function(k){ return starhope._storage[k]; },
      set: function(k, v){ starhope._storage[k] = v; sendMessage('StarhopeStorage', JSON.stringify([k, v])); return v; },
      remove: function(k){ delete starhope._storage[k]; sendMessage('StarhopeStorage', JSON.stringify(['__remove__', k])); },
      keys: function(){ return Object.keys(starhope._storage); },
      all: function(){ return JSON.parse(JSON.stringify(starhope._storage)); },
    };
    starhope.random = function(max){ return Math.floor(Math.random() * max); };
    starhope.randomInt = function(min, max){ return Math.floor(Math.random() * (max - min + 1)) + min; };
    starhope.rerender = function(){ sendMessage('Rerender', '{}'); };
  ''';

  /// 调用插件 render()，返回 widget 树 JSON 字符串（无 render 返回诊断 JSON）。
  String? renderJson() {
    final r = _rt.evaluate(
        "typeof render === 'function' ? JSON.stringify(render()) : ''");
    if (r.isError) {
      return jsonEncode({
        'type': 'text',
        'text': 'render() 出错：${r.stringResult}',
        'color': 'error',
        'size': 13,
      });
    }
    final s = r.stringResult;
    if (s.isEmpty) {
      return jsonEncode({
        'type': 'text',
        'text': '插件未定义 render 函数（main.js 可能执行失败）',
        'color': 'error',
        'size': 13,
      });
    }
    return s == 'null' ? null : s;
  }

  /// 调用插件 onAction(name, args)。
  void action(String name, [Map<String, dynamic>? args]) {
    final a = args == null ? '' : ', ${jsonEncode(args)}';
    _rt.evaluate("typeof onAction === 'function' && onAction('$name'$a);");
  }

  /// 插件标题（main.js 可设置 starhope.title 或 render 顶层 title）。
  String get title {
    final r = _rt.evaluate(
        "typeof starhope !== 'undefined' && starhope.title ? starhope.title : ''");
    final s = r.stringResult;
    return s.isEmpty ? id : s;
  }

  void dispose() => _rt.dispose();
}
