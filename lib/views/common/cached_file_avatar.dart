import 'dart:io';

import 'package:flutter/material.dart';

/// 带文件缓存的圆形头像。
///
/// 解决热路径性能问题：原先 `UserAvatar` / `avatarCircle` 每次 build 都做阻塞式
/// `File(path).existsSync()` 并 `new FileImage(...)`——流式聊天/答题时每个 token
/// 批次 rebuild 都会触发一次磁盘 IO 且无法命中图片缓存。
///
/// 现改为：`initState` 里 stat 一次并把 `FileImage` 实例缓存到 State；`FileImage`
/// 同一实例复用才能命中 Flutter 图片缓存。[path] 变化时（`didUpdateWidget`）重载。
/// 行为保持：文件存在显示图片，否则显示 [fallback]。
class CachedFileCircleAvatar extends StatefulWidget {
  final String? path;
  final double radius;
  final Color? backgroundColor;
  final Widget fallback;

  const CachedFileCircleAvatar({
    super.key,
    this.path,
    required this.radius,
    this.backgroundColor,
    required this.fallback,
  });

  @override
  State<CachedFileCircleAvatar> createState() => _CachedFileCircleAvatarState();
}

class _CachedFileCircleAvatarState extends State<CachedFileCircleAvatar> {
  FileImage? _image;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant CachedFileCircleAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _reload();
  }

  void _reload() {
    final p = widget.path;
    _image = (p != null && p.isNotEmpty && File(p).existsSync())
        ? FileImage(File(p))
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor:
          widget.backgroundColor ?? Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: _image,
      child: _image == null ? widget.fallback : null,
    );
  }
}
