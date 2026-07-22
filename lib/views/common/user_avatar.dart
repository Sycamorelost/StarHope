import 'dart:io';

import 'package:flutter/material.dart';

/// 用户头像：若设置了 avatarPath 显示图片，否则显示昵称首字母。
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
    final hasImage = avatarPath != null && avatarPath!.isNotEmpty && File(avatarPath!).existsSync();
    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primaryContainer,
      backgroundImage: hasImage ? FileImage(File(avatarPath!)) : null,
      child: hasImage
          ? null
          : Text(
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
