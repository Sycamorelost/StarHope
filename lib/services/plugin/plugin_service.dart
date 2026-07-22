import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/plugin_format.dart';
import '../database/database.dart';
import '../storage_config.dart';

/// 插件服务：目录定位、安装/卸载/启用/参数、扫描对账、导出（含署名）。
class PluginService {
  final AppDatabase _db = AppDatabase.instance;

  /// 插件根目录：<dataRoot>/plugins/
  Future<Directory> pluginsDir() async {
    final root = await StorageConfig.dataRoot();
    return Directory(p.join(root, 'plugins'));
  }

  /// 单个插件目录：<dataRoot>/plugins/<id>/
  Future<Directory> pluginDir(String id) async {
    final root = await StorageConfig.dataRoot();
    return Directory(p.join(root, 'plugins', id));
  }

  Future<List<Map<String, Object?>>> loadAll() => _db.loadPlugins();

  Future<Map<String, Object?>?> getById(String id) => _db.getPlugin(id);

  /// 安装插件包（.starhope-plugin）：校验 → 解压到 plugins/<id>/ → 入库（默认禁用）。
  /// 返回插件 id；校验失败抛异常。
  Future<String> install(String packPath) async {
    final (pack, error) = PluginFile.loadAndVerify(packPath);
    if (error != null || pack == null) throw Exception(error ?? '解析失败');
    final manifest = pack.manifest;

    final dir = await pluginDir(manifest.id);
    if (await dir.exists()) {
      await dir.delete(recursive: true); // 重装覆盖
    }
    await dir.create(recursive: true);

    final manifestJson =
        const JsonEncoder.withIndent('  ').convert(manifest.toJson());
    await File(p.join(dir.path, 'manifest.json')).writeAsString(manifestJson);
    for (final entry in pack.files.entries) {
      final f = File(p.join(dir.path, entry.key));
      await f.parent.create(recursive: true);
      await f.writeAsBytes(entry.value);
    }

    final sha = sha256.convert(utf8.encode(manifestJson)).toString();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.upsertPlugin({
      'id': manifest.id,
      'dir_name': manifest.id,
      'display_name': manifest.name,
      'version': manifest.version,
      'author': manifest.author?.display ?? '匿名',
      'description': manifest.description ?? '',
      'manifest_sha256': sha,
      'enabled': 0,
      'params_json': null,
      'installed_at': now,
      'updated_at': now,
    });
    return manifest.id;
  }

  /// 卸载：删目录 + 删库。
  Future<void> uninstall(String id) async {
    final dir = await pluginDir(id);
    if (await dir.exists()) await dir.delete(recursive: true);
    await _db.deletePlugin(id);
  }

  Future<void> setEnabled(String id, bool v) => _db.setPluginEnabled(id, v);

  Future<void> setParams(String id, String paramsJson) =>
      _db.setPluginParams(id, paramsJson);

  /// 扫描 plugins/ 目录与 DB 对账：磁盘新增登记、磁盘缺失摘除。
  Future<void> scanAndSync() async {
    final dir = await pluginsDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      return;
    }
    final dbRows = await _db.loadPlugins();
    final dbIds = dbRows.map((r) => r['id'] as String).toSet();
    final diskIds = <String>{};
    await for (final sub in dir.list(recursive: false, followLinks: false)) {
      if (sub is! Directory) continue;
      final id = p.basename(sub.path);
      final manifestFile = File(p.join(sub.path, 'manifest.json'));
      if (!await manifestFile.exists()) continue;
      diskIds.add(id);
      if (!dbIds.contains(id)) {
        try {
          final j = jsonDecode(await manifestFile.readAsString())
              as Map<String, dynamic>;
          final m = PluginManifest.fromJson(j);
          final sha = sha256.convert(await manifestFile.readAsBytes()).toString();
          final now = DateTime.now().millisecondsSinceEpoch;
          await _db.upsertPlugin({
            'id': m.id,
            'dir_name': id,
            'display_name': m.name,
            'version': m.version,
            'author': m.author?.display ?? '匿名',
            'description': m.description ?? '',
            'manifest_sha256': sha,
            'enabled': 0,
            'params_json': null,
            'installed_at': now,
            'updated_at': now,
          });
        } catch (_) {
          // 损坏的插件目录跳过
        }
      }
    }
    for (final id in dbIds) {
      if (!diskIds.contains(id)) {
        await _db.deletePlugin(id);
      }
    }
  }

  /// 导出插件为 .starhope-plugin 文件。
  /// [author] 非 null 时绑定署名（作者选担署名则填个人信息）。
  Future<void> exportPlugin(String id, String destPath,
      {PluginAuthor? author}) async {
    final dir = await pluginDir(id);
    final manifestFile = File(p.join(dir.path, 'manifest.json'));
    if (!await manifestFile.exists()) throw Exception('插件文件缺失');
    final j =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    var manifest = PluginManifest.fromJson(j);
    if (author != null) {
      manifest = PluginManifest(
        app: manifest.app,
        id: manifest.id,
        name: manifest.name,
        version: manifest.version,
        description: manifest.description,
        entry: manifest.entry,
        permissions: manifest.permissions,
        author: author,
        extensions: manifest.extensions,
        paramsSchema: manifest.paramsSchema,
      );
    }
    final files = <String, Uint8List>{};
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: dir.path);
        if (rel != 'manifest.json') {
          files[rel] = await entity.readAsBytes();
        }
      }
    }
    await PluginFile.write(path: destPath, manifest: manifest, files: files);
  }

  /// 读取插件图标 bytes（icon.png），无则返回 null。
  Future<Uint8List?> iconBytes(String id) async {
    final dir = await pluginDir(id);
    final f = File(p.join(dir.path, 'icon.png'));
    if (await f.exists()) return f.readAsBytes();
    return null;
  }

  /// 读取插件清单（plugins/<id>/manifest.json）。
  Future<PluginManifest?> manifestOf(String id) async {
    final dir = await pluginDir(id);
    final f = File(p.join(dir.path, 'manifest.json'));
    if (!await f.exists()) return null;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return PluginManifest.fromJson(j);
    } catch (_) {
      return null;
    }
  }
}
