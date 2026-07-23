import 'package:flutter/material.dart';

import 'cached_file_avatar.dart';

/// 用户头像：若设置了 avatarPath 显示图片，否则显示昵称首字母。
/// 图片加载委托给 [CachedFileCircleAvatar]（stat 一次 + 缓存 FileImage）。
class UserAvatar extends StatelessWidget {
  final String? avatarPath;
  final String nickname;
  final double radius;
  const UserAvatar({
    super.key,
    this.avatarPath,
    required this.nickname,
    this.radius = 32,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CachedFileCircleAvatar(
      path: avatarPath,
      radius: radius,
      backgroundColor: cs.primaryContainer,
      fallback: Text(
        (nickname.isEmpty ? '?' : nickname).characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: radius * 0.75,
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
