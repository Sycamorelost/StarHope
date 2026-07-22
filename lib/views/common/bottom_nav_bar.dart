import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/home_nav_provider.dart';
import 'glass.dart';
import 'user_avatar.dart';

/// 底部圆边毛玻璃导航：5 项，中间（摘要）为圆形用户头像突起（不显示菜单名），
/// 其余为稍大的圆形图标按钮 + 标签。
class StarBottomNav extends StatelessWidget {
  const StarBottomNav({super.key});

  static const _items = <({HomeTab tab, IconData? icon, String label})>[
    (tab: HomeTab.learningTools, icon: Icons.school_outlined, label: '学习'),
    (tab: HomeTab.plugins, icon: Icons.extension_outlined, label: '插件'),
    (tab: HomeTab.summary, icon: null, label: ''),
    (tab: HomeTab.ai, icon: Icons.smart_toy_outlined, label: 'AI'),
    (tab: HomeTab.settings, icon: Icons.settings_outlined, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<HomeNavProvider>();
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final it in _items)
              _item(context, it, nav.tab == it.tab, cs, auth),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context,
      ({HomeTab tab, IconData? icon, String label}) it, bool selected,
      ColorScheme cs, AuthProvider auth) {
    if (it.tab == HomeTab.summary) {
      // 中间：圆形用户头像（突起），不显示菜单名
      return GestureDetector(
        onTap: () => context.read<HomeNavProvider>().switchTo(it.tab),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? cs.primary : Colors.transparent, width: 2),
          ),
          padding: const EdgeInsets.all(2),
          child: UserAvatar(
            avatarPath: auth.user?.avatarPath,
            nickname: auth.user?.nickname ?? '?',
            radius: 20,
          ),
        ),
      );
    }
    final iconColor = selected ? cs.onPrimary : cs.onSurfaceVariant;
    return GestureDetector(
      onTap: () => context.read<HomeNavProvider>().switchTo(it.tab),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? cs.primary : Colors.transparent,
            ),
            child: Icon(it.icon, size: 20, color: iconColor),
          ),
          const SizedBox(height: 2),
          Text(it.label,
              style: TextStyle(
                  fontSize: 10,
                  color: selected ? cs.primary : cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
