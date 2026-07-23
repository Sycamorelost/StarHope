import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'constants.dart';
import 'models/share_meta.dart';

/// .starhope 文件格式 —— 导出 / 导入 / 防伪校验（核心层）
///
/// 文件结构（ZIP）：
///   meta.json     —— 头部：魔数、版本、分享者信息、内容类型、校验和、文件清单
///   payload.json  —— 负载：题目 / 笔记 / 资料元数据
///   files/<name>  —— 附件二进制（资料文件）
///
/// 防伪：头部 [payloadSha256] 为 payload.json 字节的 SHA-256；导入时重算比对。
///      每个附件文件单独记录 SHA-256，逐一校验。
class StarHopeFile {
  final ShareMeta meta;
  final Map<String, dynamic> payload;
  final Map<String, Uint8List> files;

  const StarHopeFile({
    required this.meta,
    required this.payload,
    this.files = const {},
  });

  /// 从磁盘读取并校验完整性
  /// 返回 (file, error)。error 非空表示校验失败（疑似篡改）。
  static (StarHopeFile?, String?) loadAndVerify(String path) {
    final bytes = File(path).readAsBytesSync();
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return (null, '无法解析 .starhope 文件（非有效 ZIP）');
    }

    String readArchiveFile(String name) {
      final f = archive.findFile(name);
      if (f == null) throw Exception('缺少文件: $name');
      return utf8.decode(f.content as List<int>);
    }

    Uint8List readArchiveBinary(String name) {
      final f = archive.findFile(name);
      if (f == null) throw Exception('缺少附件: $name');
      return Uint8List.fromList(f.content as List<int>);
    }

    Map<String, dynamic> metaJson;
    String payloadJson;
    try {
      metaJson = jsonDecode(readArchiveFile('meta.json')) as Map<String, dynamic>;
      payloadJson = readArchiveFile('payload.json');
    } catch (e) {
      return (null, '文件结构损坏: $e');
    }

    if (metaJson['magic'] != AppConstants.magic) {
      return (null, '魔数不匹配，非 StarHope 文件');
    }

    final expectedPayloadHash = metaJson['payload_sha256'] as String? ?? '';
    final actualPayloadHash =
        sha256.convert(utf8.encode(payloadJson)).toString();
    if (!_constTimeEq(expectedPayloadHash, actualPayloadHash)) {
      return (null, '负载摘要校验失败 —— 文件可能被篡改');
    }

    final meta = ShareMeta.fromJson(
        metaJson['author'] as Map<String, dynamic>? ?? <String, dynamic>{});

    // 校验附件
    final filesList = (metaJson['files'] as List?) ?? const [];
    final files = <String, Uint8List>{};
    for (final entry in filesList) {
      final e = entry as Map<String, dynamic>;
      final name = e['name'] as String;
      final expectedHash = e['sha256'] as String;
      final data = readArchiveBinary('files/$name');
      final actualHash = sha256.convert(data).toString();
      if (!_constTimeEq(expectedHash, actualHash)) {
        return (null, '附件「$name」摘要校验失败 —— 文件可能被篡改');
      }
      files[name] = data;
    }

    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
    return (StarHopeFile(meta: meta, payload: payload, files: files), null);
  }

  /// 导出为 .starhope 文件
  /// [payload] 负载对象；[files] 附件（文件名 -> 字节）
  static Future<void> write({
    required String path,
    required ShareMeta meta,
    required Map<String, dynamic> payload,
    Map<String, Uint8List> files = const {},
  }) async {
    final payloadJson = _prettyJson(payload);
    final payloadHash = sha256.convert(utf8.encode(payloadJson)).toString();

    final fileList = <Map<String, dynamic>>[];
    for (final entry in files.entries) {
      fileList.add({
        'name': entry.key,
        'sha256': sha256.convert(entry.value).toString(),
        'size': entry.value.length,
      });
    }

    final metaJson = {
      'magic': AppConstants.magic,
      'format_version': AppConstants.formatVersion,
      'author': meta.toJson(),
      'content_type': meta.contentType.name,
      'exported_at': meta.exportedAt,
      'payload_sha256': payloadHash,
      'files': fileList,
    };

    final archive = Archive();
    final metaBytes = Uint8List.fromList(utf8.encode(_prettyJson(metaJson)));
    final payloadBytes = Uint8List.fromList(utf8.encode(payloadJson));
    archive.addFile(ArchiveFile('meta.json', metaBytes.length, metaBytes));
    archive.addFile(
        ArchiveFile('payload.json', payloadBytes.length, payloadBytes));
    for (final entry in files.entries) {
      archive.addFile(
          ArchiveFile('files/${entry.key}', entry.value.length, entry.value));
    }

    final zipBytes = ZipEncoder().encode(archive)!;
    await File(path).writeAsBytes(zipBytes, flush: true);
  }

  static String _prettyJson(Object o) =>
      const JsonEncoder.withIndent('  ').convert(o);

  static bool _constTimeEq(String a, String b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return r == 0;
  }
}

