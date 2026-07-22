import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/crypto/crypto_service.dart';
import '../core/models/models.dart';
import 'storage_config.dart';

/// 文件存储服务（服务层）
///
/// 将导入的阅读资料复制到用户指定的数据目录，文件名以随机 ID 命名，避免覆盖。
class FileStorageService {
  static Future<Directory> materialsDir() async {
    final base = await StorageConfig.dataRoot();
    final dir = Directory(p.join(base, 'materials'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 复制源文件到私有目录，返回新路径与文件大小
  static Future<({String storedPath, int sizeBytes})> importFile(
      String sourcePath) async {
    final dir = await materialsDir();
    final ext = p.extension(sourcePath);
    final id = CryptoService.generateId();
    final dest = p.join(dir.path, '$id$ext');
    await File(sourcePath).copy(dest);
    final size = await File(dest).length();
    return (storedPath: dest, sizeBytes: size);
  }

  /// 从字节直接写入（用于导入 .starhope 包内附件）
  static Future<String> writeBytes(
      String originalName, List<int> bytes) async {
    final dir = await materialsDir();
    final ext = p.extension(originalName);
    final id = CryptoService.generateId();
    final dest = p.join(dir.path, '$id$ext');
    await File(dest).writeAsBytes(bytes, flush: true);
    return dest;
  }

  static Future<void> delete(String storedPath) async {
    final f = File(storedPath);
    if (await f.exists()) await f.delete();
  }

  /// 保存头像：校验 ≤2MB，复制到私有目录，返回新路径。
  /// 文件过大或非图片时抛异常。
  static Future<String> saveAvatar(String sourcePath) async {
    final f = File(sourcePath);
    final size = await f.length();
    if (size > 2 * 1024 * 1024) {
      throw ArgumentError('头像文件过大（${(size / 1024 / 1024).toStringAsFixed(1)}MB），请选择不超过 2MB 的图片');
    }
    final ext = p.extension(sourcePath).toLowerCase();
    const allowed = {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'};
    if (ext.isNotEmpty && !allowed.contains(ext)) {
      throw ArgumentError('不支持的图片格式 $ext，请选择 png/jpg/jpeg/webp/bmp/gif');
    }
    final dir = await materialsDir();
    final avatarDir = Directory(p.join(dir.path, 'avatars'));
    if (!avatarDir.existsSync()) avatarDir.createSync(recursive: true);
    final id = CryptoService.generateId();
    final dest = p.join(avatarDir.path, '$id${ext.isEmpty ? '.png' : ext}');
    await f.copy(dest);
    return dest;
  }

  /// AI 对话附件目录（图片与文本类附件的私有副本）
  static Future<Directory> attachmentsDir() async {
    final base = await StorageConfig.dataRoot();
    final dir = Directory(p.join(base, 'materials', 'attachments'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 导入附件：复制到私有目录，返回元信息。MIME 由文件名扩展名推断。
  /// 调用方负责大小/数量校验。
  static Future<AttachmentMeta> importAttachment({
    required String sourcePath,
    required String fileName,
  }) async {
    final dir = await attachmentsDir();
    final ext = p.extension(sourcePath);
    final id = CryptoService.generateId();
    final dest = p.join(dir.path, '$id$ext');
    await File(sourcePath).copy(dest);
    final size = await File(dest).length();
    final mime = mimeOfFileName(fileName);
    return AttachmentMeta(
      id: id,
      fileName: fileName,
      mimeType: mime,
      storedPath: dest,
      isImage: mime.startsWith('image/'),
      sizeBytes: size,
    );
  }

  /// 按文件名扩展名推断 MIME（避免引入 package:mime 依赖）
  static String mimeOfFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.md')) return 'text/markdown';
    return 'text/plain';
  }

  static Future<void> deleteAttachment(String storedPath) async {
    final f = File(storedPath);
    if (await f.exists()) await f.delete();
  }

  /// 清空全部附件（恢复出厂时由调用方在 DB clearAll 之后调用）
  static Future<void> clearAttachments() async {
    final dir = await attachmentsDir();
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
