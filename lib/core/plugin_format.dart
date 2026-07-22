import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'constants.dart';

/// 插件作者署名（可选——作者选择署名时绑定个人信息）。
class PluginAuthor {
  final String? nickname;
  final String? account;
  final String? github;
  final bool signed; // 是否署名绑定

  const PluginAuthor({
    this.nickname,
    this.account,
    this.github,
    this.signed = false,
  });

  Map<String, dynamic> toJson() => {
        if (nickname != null) 'nickname': nickname,
        if (account != null) 'account': account,
        if (github != null) 'github': github,
        'signed': signed,
      };

  static PluginAuthor? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    return PluginAuthor(
      nickname: j['nickname'] as String?,
      account: j['account'] as String?,
      github: j['github'] as String?,
      signed: j['signed'] as bool? ?? false,
    );
  }

  /// 展示用署名文本。
  String get display => nickname ?? account ?? github ?? '匿名';
}

/// 插件清单（manifest.json）。
///
/// 严格规范：必须 [app]=='StarHope'（署本应用名）+ [id] 以 'shp.' 开头（专有名，
/// 绑定本应用流通、防泛滥）。
class PluginManifest {
  final String app; // 必须 'StarHope'
  final String id; // 'shp.<author>.<name>' 专有名
  final String name;
  final String version;
  final String? description;
  final String entry; // 入口脚本（如 'main.js'）
  final List<String> permissions;
  final PluginAuthor? author;
  final List<Map<String, dynamic>> extensions; // 扩展点（阶段 3 解析执行）
  final Map<String, dynamic> paramsSchema; // 参数 schema（动态表单）

  const PluginManifest({
    required this.app,
    required this.id,
    required this.name,
    required this.version,
    this.description,
    required this.entry,
    this.permissions = const [],
    this.author,
    this.extensions = const [],
    this.paramsSchema = const {},
  });

  Map<String, dynamic> toJson() => {
        'app': app,
        'magic': AppConstants.pluginMagic,
        'format_version': AppConstants.pluginFormatVersion,
        'id': id,
        'name': name,
        'version': version,
        if (description != null) 'description': description,
        'entry': entry,
        'permissions': permissions,
        'extensions': extensions,
        'params_schema': paramsSchema,
        if (author != null) 'author': author!.toJson(),
      };

  /// 从原始 JSON 解析（不做校验）。
  static PluginManifest fromJson(Map<String, dynamic> j) {
    return PluginManifest(
      app: j['app'] as String? ?? '',
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      version: j['version'] as String? ?? '',
      description: j['description'] as String?,
      entry: j['entry'] as String? ?? 'main.js',
      permissions: (j['permissions'] as List?)?.cast<String>() ?? const [],
      author: PluginAuthor.fromJson(j['author'] as Map<String, dynamic>?),
      extensions:
          (j['extensions'] as List?)?.cast<Map<String, dynamic>>() ?? const [],
      paramsSchema:
          (j['params_schema'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

/// 插件包（.starhope-plugin，ZIP）：manifest + 文件（main.js/资源）。
class PluginPack {
  final PluginManifest manifest;
  final Map<String, Uint8List> files;

  const PluginPack({required this.manifest, required this.files});
}

/// 插件包读写 + 防伪校验。
class PluginFile {
  PluginFile._();

  static const _json = JsonEncoder.withIndent('  ');

  /// 从磁盘读取并校验。返回 (pack, error)，error 非空表示不可导入。
  static (PluginPack?, String?) loadAndVerify(String path) {
    final bytes = File(path).readAsBytesSync();
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return (null, '无法解析插件包（非有效 ZIP）');
    }

    String readFile(String name) {
      final f = archive.findFile(name);
      if (f == null) throw Exception('缺少文件: $name');
      return utf8.decode(f.content as List<int>);
    }

    Uint8List readBinary(String name) {
      final f = archive.findFile(name);
      if (f == null) throw Exception('缺少文件: $name');
      return Uint8List.fromList(f.content as List<int>);
    }

    Map<String, dynamic> manifestJson;
    try {
      manifestJson =
          jsonDecode(readFile('manifest.json')) as Map<String, dynamic>;
    } catch (e) {
      return (null, 'manifest.json 损坏: $e');
    }

    // 严格校验：魔数
    if (manifestJson['magic'] != AppConstants.pluginMagic) {
      return (null, '魔数不匹配，非 StarHope 插件');
    }
    // 严格校验：归属本应用（署 StarHope 名）
    if (manifestJson['app'] != AppConstants.appName) {
      return (null, '该插件不属于 StarHope 应用（app 字段不匹配）');
    }
    // 严格校验：专有名（shp. 前缀，防泛滥）
    final id = manifestJson['id'] as String? ?? '';
    if (!id.startsWith(AppConstants.pluginIdPrefix) ||
        id.length <= AppConstants.pluginIdPrefix.length) {
      return (null, '插件专有名不合法（须以 "${AppConstants.pluginIdPrefix}" 开头）');
    }

    final manifest = PluginManifest.fromJson(manifestJson);

    // 校验入口文件存在
    if (archive.findFile(manifest.entry) == null) {
      return (null, '缺少入口文件: ${manifest.entry}');
    }

    // 读取并校验所有文件（manifest.files 清单的 SHA-256）
    final filesList = (manifestJson['files'] as List?) ?? const [];
    final files = <String, Uint8List>{};
    for (final entry in filesList) {
      final e = entry as Map<String, dynamic>;
      final name = e['name'] as String;
      final expectedHash = e['sha256'] as String;
      final data = readBinary(name);
      final actualHash = sha256.convert(data).toString();
      if (!_constTimeEq(expectedHash, actualHash)) {
        return (null, '文件「$name」摘要校验失败 —— 插件可能被篡改');
      }
      files[name] = data;
    }
    // 入口文件若未在清单也要读入
    if (!files.containsKey(manifest.entry)) {
      files[manifest.entry] = readBinary(manifest.entry);
    }

    return (PluginPack(manifest: manifest, files: files), null);
  }

  /// 导出为 .starhope-plugin 文件。
  /// [manifest] 须含完整署名/专有名；[files] 文件名 -> 字节（main.js 等）。
  static Future<void> write({
    required String path,
    required PluginManifest manifest,
    Map<String, Uint8List> files = const {},
  }) async {
    final fileList = <Map<String, dynamic>>[];
    for (final entry in files.entries) {
      fileList.add({
        'name': entry.key,
        'sha256': sha256.convert(entry.value).toString(),
        'size': entry.value.length,
      });
    }

    final manifestJson = Map<String, dynamic>.from(manifest.toJson());
    manifestJson['files'] = fileList;
    manifestJson['exported_at'] = DateTime.now().millisecondsSinceEpoch;

    final archive = Archive();
    final manifestBytes = Uint8List.fromList(utf8.encode(_json.convert(manifestJson)));
    archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }

    final zipBytes = ZipEncoder().encode(archive)!;
    await File(path).writeAsBytes(zipBytes, flush: true);
  }

  static bool _constTimeEq(String a, String b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return r == 0;
  }
}
