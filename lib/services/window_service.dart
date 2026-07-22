import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 窗口控制服务（桌面）。
///
/// 通过 win32 FFI 查找本应用的 HWND 并执行无边框窗口的最小化/最大化/关闭/拖动/全屏。
/// 窗口类名由 Flutter Windows runner 定义为 FLUTTER_RUNNER_WIN32_WINDOW。
class WindowService {
  static int? _hwnd;
  static const _className = 'FLUTTER_RUNNER_WIN32_WINDOW';

  static int _findHwnd() {
    if (_hwnd != null && IsWindow(_hwnd!) != 0) return _hwnd!;
    final cls = _className.toNativeUtf16(allocator: calloc);
    try {
      _hwnd = FindWindowEx(0, 0, cls, Pointer.fromAddress(0));
    } finally {
      calloc.free(cls);
    }
    return _hwnd ?? 0;
  }

  static bool get available => _findHwnd() != 0;

  static void minimize() {
    if (_examLock) return; // 考试中禁止最小化
    final h = _findHwnd();
    if (h != 0) SendMessage(h, WM_SYSCOMMAND, SC_MINIMIZE, 0);
  }

  static void toggleMaximize() {
    if (_examLock) return;
    final h = _findHwnd();
    if (h == 0) return;
    final cmd = IsZoomed(h) != 0 ? SC_RESTORE : SC_MAXIMIZE;
    SendMessage(h, WM_SYSCOMMAND, cmd, 0);
  }

  static void close() {
    if (_examLock) return; // 考试中禁止关闭（交卷才退）
    final h = _findHwnd();
    if (h != 0) PostMessage(h, WM_CLOSE, 0, 0);
  }

  /// 隐藏窗口到系统托盘（彻底从任务栏消失，不同于 minimize）。
  static void hide() {
    final h = _findHwnd();
    if (h != 0) ShowWindow(h, SW_HIDE);
  }

  /// 从托盘恢复窗口（显示并置前）。
  static void show() {
    final h = _findHwnd();
    if (h != 0) {
      ShowWindow(h, SW_SHOW);
      SetForegroundWindow(h);
    }
  }

  /// 开始拖动窗口（在自定义标题栏按下时调用）。
  static void startDrag() {
    if (!_dragEnabled) return; // 考试全屏中禁拖
    final h = _findHwnd();
    if (h == 0) return;
    ReleaseCapture();
    SendMessage(h, WM_NCLBUTTONDOWN, HTCAPTION, 0);
  }

  // ==================== 考试锁定 ====================
  static bool _dragEnabled = true; // false 时标题栏拖动失效
  static bool _examLock = false; // true 时禁止最小化/关闭/最大化
  static bool get isExamLocked => _examLock;

  /// 进入考试模式：真全屏 + 禁拖 + 禁系统按钮（交卷才退）。
  static void enterExamMode() {
    if (!_fullscreen) toggleFullscreen();
    _dragEnabled = false;
    _examLock = true;
  }

  /// 退出考试模式：恢复窗口 + 解禁。
  static void exitExamMode() {
    if (_fullscreen) toggleFullscreen();
    _dragEnabled = true;
    _examLock = false;
  }

  // ==================== 置顶 ====================
  static bool _topmost = false;
  static bool get isTopmost => _topmost;

  /// 切换窗口置顶（保持在最顶层）。
  static void toggleTopmost() {
    final h = _findHwnd();
    if (h == 0) return;
    _topmost = !_topmost;
    SetWindowPos(
        h,
        _topmost ? HWND_TOPMOST : HWND_NOTOPMOST,
        0,
        0,
        0,
        0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  }

  // ==================== 全屏 ====================
  static bool _fullscreen = false;
  static int _savedLeft = 0, _savedTop = 0, _savedW = 0, _savedH = 0;

  static bool get isFullscreen => _fullscreen;

  /// 切换真全屏：覆盖整个显示器（含任务栏），置顶；退出时恢复。
  static void toggleFullscreen() {
    final h = _findHwnd();
    if (h == 0) return;
    if (!_fullscreen) {
      // 保存当前窗口矩形
      final rc = calloc<RECT>();
      try {
        GetWindowRect(h, rc);
        _savedLeft = rc.ref.left;
        _savedTop = rc.ref.top;
        _savedW = rc.ref.right - rc.ref.left;
        _savedH = rc.ref.bottom - rc.ref.top;
      } finally {
        calloc.free(rc);
      }
      // 铺满显示器并置顶
      final monitor = MonitorFromWindow(h, MONITOR_DEFAULTTONEAREST);
      final info = calloc<MONITORINFO>();
      try {
        info.ref.cbSize = sizeOf<MONITORINFO>();
        if (GetMonitorInfo(monitor, info) != 0) {
          final m = info.ref.rcMonitor;
          SetWindowPos(h, HWND_TOPMOST, m.left, m.top,
              m.right - m.left, m.bottom - m.top,
              SWP_FRAMECHANGED | SWP_SHOWWINDOW);
        }
      } finally {
        calloc.free(info);
      }
      _fullscreen = true;
    } else {
      // 退出全屏：恢复矩形，取消置顶
      SetWindowPos(h, HWND_NOTOPMOST, _savedLeft, _savedTop, _savedW, _savedH,
          SWP_FRAMECHANGED | SWP_SHOWWINDOW);
      _fullscreen = false;
    }
  }
}
