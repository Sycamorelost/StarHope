import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 数据存储位置配置（引导层）。
///
/// 配置文件本身固定存放在系统应用支持目录（便于启动时读取），
/// 而实际的数据库与资料文件存放在用户通过设置指定的 [dataRoot]。
/// 默认 [dataRoot] 即应用支持目录本身。
class StorageConfig {
  StorageConfig._();

  /// 引导配置文件（固定位置，永不被迁移）
  static Future<File> _configFile() async {
    final base = await getApplicationSupportDirectory();
    return File(p.join(base.path, 'storage_config.json'));
  }

  /// 当前数据根目录。若用户未指定或目录不可用，回退到应用支持目录。
  static Future<String> dataRoot() async {
    final cfg = await _configFile();
    if (await cfg.exists()) {
      try {
        final j = jsonDecode(await cfg.readAsString()) as Map<String, dynamic>;
        final root = j['dataRoot'] as String?;
        if (root != null && root.isNotEmpty && await Directory(root).exists()) {
          return root;
        }
      } catch (_) {
        // 配置损坏，回退默认
      }
    }
    return (await getApplicationSupportDirectory()).path;
  }

  /// 设置数据根目录（写入引导配置）
  static Future<void> setDataRoot(String path) async {
    final cfg = await _configFile();
    await cfg.writeAsString(jsonEncode({'dataRoot': path}));
  }

  /// 将当前数据根目录下的所有数据复制到新位置（数据库 + 资料）。
  /// 返回复制的文件数。不删除原位置数据（安全起见保留）。
  static Future<int> copyDataTo(String newRoot) async {
    final oldRoot = await dataRoot();
    var count = 0;
    await Directory(newRoot).create(recursive: true);

    // 数据库文件
    final dbFile = File(p.join(oldRoot, 'starhope.db'));
    if (await dbFile.exists()) {
      await dbFile.copy(p.join(newRoot, 'starhope.db'));
      count++;
      final wal = File('${dbFile.path}-wal');
      if (await wal.exists()) {
        await wal.copy(p.join(newRoot, 'starhope.db-wal'));
      }
      final shm = File('${dbFile.path}-shm');
      if (await shm.exists()) {
        await shm.copy(p.join(newRoot, 'starhope.db-shm'));
      }
    }

    // materials 目录（资料 + 头像）
    final matsDir = Directory(p.join(oldRoot, 'materials'));
    if (await matsDir.exists()) {
      count += await _copyDir(matsDir, Directory(p.join(newRoot, 'materials')));
    }

    // plugins 目录（插件）
    final pluginsDir = Directory(p.join(oldRoot, 'plugins'));
    if (await pluginsDir.exists()) {
      count +=
          await _copyDir(pluginsDir, Directory(p.join(newRoot, 'plugins')));
    }
    return count;
  }

  static Future<int> _copyDir(Directory src, Directory dest) async {
    var n = 0;
    await dest.create(recursive: true);
    await for (final entity in src.list(recursive: false, followLinks: false)) {
      final target = p.join(dest.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(target);
        n++;
      } else if (entity is Directory) {
        n += await _copyDir(entity, Directory(target));
      }
    }
    return n;
  }
}
