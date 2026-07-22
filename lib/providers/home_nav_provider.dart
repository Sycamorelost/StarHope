import 'package:flutter/material.dart';

/// 主界面菜单项（顺序与 HomeShell._pages 一一对应）
enum HomeTab { summary, bank, wrong, practice, exam, reader, ai, plugins, settings }

/// 主界面导航状态：暴露给子页切换 Tab（例如错题本「练这些错题」切到练习页）。
class HomeNavProvider extends ChangeNotifier {
  HomeTab _tab = HomeTab.summary;
  HomeTab get tab => _tab;

  /// 全局刷新纪元：每次侧栏"刷新"按钮触发后自增，订阅方据此重载数据。
  int _refreshEpoch = 0;
  int get refreshEpoch => _refreshEpoch;

  void switchTo(HomeTab t) {
    if (_tab == t) return;
    _tab = t;
    notifyListeners();
  }

  /// 通知所有订阅方：全局数据已刷新，请重新加载。
  void bumpRefresh() {
    _refreshEpoch++;
    notifyListeners();
  }
}
