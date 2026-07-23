import 'package:flutter/material.dart';

import 'theme.dart';
import 'window_title_bar.dart';

/// 工具子页宿主：FrostedBackground + 带返回的标题栏 + 功能页。
///
/// 用于从「学习工具」「错题本」「考试」等处 push 进入的工具页（题库/练习/考试/错题本/阅读）。
/// 功能页自身 Scaffold 背景需透明，让 [FrostedBackground] 渐变透出；返回按钮在标题栏左侧。
class ToolHostPage extends StatelessWidget {
  final String title;
  final Widget child;

  const ToolHostPage({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return FrostedBackground(
      child: Column(
        children: [
          WindowTitleBar(
            title: title,
            leading: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 18),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
