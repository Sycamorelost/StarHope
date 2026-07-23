import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/practice_exam_provider.dart';
import '../../providers/question_provider.dart';
import '../../providers/reader_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/database/database.dart';
import '../../services/data_modules.dart';
import '../../services/export_service.dart';
import '../../services/file_storage_service.dart';
import '../../services/plugin/plugin_service.dart';
import '../../services/secure_storage_service.dart';
import '../../services/storage_config.dart';
import '../common/glass.dart';
import '../common/disclaimer.dart';
import 'widgets/import_export_dialogs.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ExportService _export = ExportService();
  // 数据根目录在 initState 取一次，避免内联 FutureBuilder 每次 rebuild 重读配置。
  String? _dataRoot;

  @override
  void initState() {
    super.initState();
    StorageConfig.dataRoot().then((r) {
      if (mounted) setState(() => _dataRoot = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = context.watch<ThemeProvider>();
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('设置',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          // 主题
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('外观',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.auto_mode),
                        label: Text('跟随系统')),
                    ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('浅色')),
                    ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('深色')),
                  ],
                  selected: {theme.mode},
                  onSelectionChanged: (s) => theme.setMode(s.first),
                ),
                const SizedBox(height: 12),
                Divider(
                    height: 1,
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.3)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('回车键发送 / 确认'),
                          Text(
                              '开启：AI 对话按 Enter 发送（Shift+Enter 换行）；登录页回车确认始终可用',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Switch(
                      value: theme.enterToSend,
                      onChanged: (v) => theme.setEnterToSend(v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 数据分享与备份
          _sectionTitle('数据分享与备份'),
          _menuTile(
            icon: Icons.download_for_offline_outlined,
            title: '导入 .starhope 题库',
            subtitle: '校验完整性后并入题库，显示分享者信息',
            onTap: () => showImportStarHopeDialog(context),
          ),
          _menuTile(
            icon: Icons.backup_outlined,
            title: '全库备份',
            subtitle: '勾选要备份的模块（题库/资料/笔记/历史/插件等，不含 AI 密钥）',
            onTap: () => _fullBackup(context, auth),
          ),
          _menuTile(
            icon: Icons.restore_outlined,
            title: '从备份恢复',
            subtitle: '选择要恢复的模块，仅替换对应数据，其它不受影响',
            onTap: () => _restore(context, auth),
          ),
          const SizedBox(height: 8),
          // 数据存储位置
          _sectionTitle('数据存储位置'),
          _menuTile(
            icon: Icons.folder_open_outlined,
            title: '打开资源文件夹',
            subtitle: _dataRoot ?? '加载中…',
            onTap: () => _openDataFolder(),
          ),
          _menuTile(
            icon: Icons.drive_folder_upload_outlined,
            title: '更改存储位置',
            subtitle: '将所有数据（题库/资料/笔记/历史）保存到指定文件夹，重启后生效',
            onTap: () => _changeDataLocation(context),
          ),
          const SizedBox(height: 16),
          // 快捷键与安全
          _sectionTitle('快捷键与安全'),
          _menuTile(
            icon: Icons.close_rounded,
            title: '关闭窗口行为',
            subtitle: '当前：${_closeActionLabel(theme.closeAction)}',
            onTap: () => _chooseCloseAction(context, theme),
          ),
          _switchTile(
            icon: Icons.lock_clock_outlined,
            title: '最小化到托盘时自动锁定',
            subtitle: '隐藏到托盘时立即锁定账户，需重新登录',
            value: theme.lockOnHide,
            onChanged: (v) => theme.setLockOnHide(v),
          ),
          _menuTile(
            icon: Icons.lock_outline,
            title: '锁定热键',
            subtitle: '当前：${_hotkeyLabel(theme.lockHotkey)}（应用内按下即锁定回登录页）',
            onTap: () => _recordHotkey(context, theme),
          ),
          _menuTile(
            icon: Icons.delete_forever_outlined,
            title: '删除数据（可选模块）',
            subtitle: '勾选要删除的数据类型（题库/错题/历史/资料/AI 等），可选是否删账户',
            onTap: () => _factoryReset(context, auth),
          ),
          const SizedBox(height: 16),
          // 关于
          _sectionTitle('关于'),
          _menuTile(
            icon: Icons.info_outline,
            title: 'StarHope',
            subtitle: '版本 1.0.0 · 本地化学习助手',
            onTap: () {},
          ),
          _menuTile(
            icon: Icons.security_outlined,
            title: '安全说明',
            subtitle: '密码 PBKDF2 加盐哈希；AI 密钥 AES-GCM 加密、仅存内存；导入文件 SHA-256 校验',
            onTap: () {},
          ),
          const SizedBox(height: 16),
          // 退出
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
                foregroundColor: Colors.red,
                backgroundColor: Colors.red.withValues(alpha: 0.08)),
            onPressed: () => _logout(context, auth),
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
          ),
          const SizedBox(height: 24),
          // 赞赏栏
          _donateBar(context),
          const SizedBox(height: 12),
          // 免责声明
          _menuTile(
            icon: Icons.gavel_outlined,
            title: '免责声明',
            subtitle: '软件使用条款与责任限制（署名：梧桐吾桐）',
            onTap: () => showDisclaimerDialog(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _hotkeyLabel(String encoded) {
    final dot = encoded.indexOf('.');
    if (dot < 0) return encoded;
    final mod = encoded.substring(0, dot);
    final key = encoded.substring(dot + 1).toUpperCase();
    final modLabel = mod == 'ctrl'
        ? 'Ctrl'
        : mod == 'alt'
            ? 'Alt'
            : mod == 'shift'
                ? 'Shift'
                : mod;
    return '$modLabel + $key';
  }

  void _recordHotkey(BuildContext context, ThemeProvider theme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('录制锁定热键'),
        content: KeyboardListener(
          focusNode: FocusNode(),
          autofocus: true,
          onKeyEvent: (e) {
            if (e is! KeyDownEvent) return;
            final hk = HardwareKeyboard.instance;
            String mod;
            if (hk.isControlPressed) {
              mod = 'ctrl';
            } else if (hk.isAltPressed) {
              mod = 'alt';
            } else if (hk.isShiftPressed) {
              mod = 'shift';
            } else {
              return; // 必须含修饰键
            }
            final key = e.logicalKey.keyLabel.toLowerCase();
            if (key.isEmpty || key.length > 2) return;
            theme.setLockHotkey('$mod.$key');
            Navigator.pop(ctx);
          },
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Text('请按下组合键（Ctrl/Alt/Shift + 字母/数字）'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
  }

  Future<void> _factoryReset(BuildContext context, AuthProvider auth) async {
    // 1. 选择要删除的模块（复用统一模块注册表）
    final modules = await _pickBackupModules(context, title: '选择删除内容');
    if (modules == null || modules.isEmpty) return;
    if (!context.mounted) return;

    final tables = DataModule.tablesFor(modules);

    // 2. 确认 + 是否删账户
    var delAccount = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('删除选中数据'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('将删除选中的 ${modules.length} 类数据，此操作不可撤销。'),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: delAccount,
                onChanged: (v) => set(() => delAccount = v ?? false),
                title: const Text('同时删除账户并注销回注册页'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    // 3. 执行删除
    final db = AppDatabase.instance;
    if (tables.isNotEmpty) await db.clearAll(tables);
    if (modules.contains('materials')) {
      await FileStorageService.clearAttachments();
    }
    if (modules.contains('plugins')) {
      await PluginService().deleteAllDirs();
    }
    if (delAccount) {
      await db.deleteUser();
      await SecureStorageService().clearAll();
      if (!context.mounted) return;
      auth.logout();
    }
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(t,
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600)),
      );

  Widget _menuTile(
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }

  String _closeActionLabel(CloseAction a) {
    switch (a) {
      case CloseAction.minimize:
        return '最小化到托盘';
      case CloseAction.exit:
        return '退出应用';
      case CloseAction.ask:
        return '每次询问';
    }
  }

  Future<void> _chooseCloseAction(
      BuildContext context, ThemeProvider theme) async {
    final chosen = await showDialog<CloseAction>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('关闭窗口行为'),
        children: [
          for (final a in CloseAction.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, a),
              child: Row(
                children: [
                  Icon(
                    a == theme.closeAction
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(_closeActionLabel(a)),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen != null) theme.setCloseAction(chosen);
  }

  /// 模块 → 图标映射（视图层负责呈现，服务层 DataModule 不含 Flutter 依赖）。
  static const _moduleIcons = <String, IconData>{
    'questions': Icons.library_books_outlined,
    'folders': Icons.folder_outlined,
    'practices': Icons.history,
    'exam_rules': Icons.school_outlined,
    'exam_results': Icons.assignment_turned_in_outlined,
    'wrong': Icons.error_outline,
    'wrong_groups': Icons.label_outline,
    'materials': Icons.menu_book_outlined,
    'ai_services': Icons.cloud_outlined,
    'ai_agents': Icons.smart_toy_outlined,
    'ai_conversations': Icons.chat_bubble_outline,
    'ai_messages': Icons.message_outlined,
    'plugins': Icons.extension,
  };

  /// 选择模块的统一对话框，备份 / 恢复 / 删除三处复用。
  /// [available] 非空时只展示这些模块（恢复时仅列备份里实际存在的模块）。
  Future<Set<String>?> _pickBackupModules(BuildContext context,
      {String title = '选择备份内容', Set<String>? available}) {
    final list = available == null
        ? DataModule.all
        : DataModule.all.where((m) => available.contains(m.id)).toList();
    final selected = <String>{for (final m in list) m.id};
    return showDialog<Set<String>?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (sctx, set) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final m in list)
                    CheckboxListTile(
                      dense: true,
                      value: selected.contains(m.id),
                      onChanged: (v) => set(() {
                        if (v == true) {
                          selected.add(m.id);
                        } else {
                          selected.remove(m.id);
                        }
                      }),
                      secondary: Icon(_moduleIcons[m.id] ?? Icons.extension,
                          size: 20),
                      title: Text(m.label),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('下一步')),
          ],
        ),
      ),
    );
  }

  Future<void> _fullBackup(BuildContext context, AuthProvider auth) async {
    final modules = await _pickBackupModules(context);
    if (modules == null) return;
    final out = await FilePicker.platform.saveFile(
      dialogTitle: '全库备份',
      fileName: 'starhope_backup_${DateTime.now().millisecondsSinceEpoch}.starhope',
    );
    if (out == null) return;
    final meta = _export.buildMeta(auth.user!, ShareContentType.fullBackup,
        publicSocial: false);
    try {
      await _export.fullBackup(
          path: out, author: auth.user!, meta: meta, modules: modules);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已备份：$out')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('备份失败：$e')));
      }
    }
  }

  Future<void> _restore(BuildContext context, AuthProvider auth) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['starhope'],
    );
    if (result == null || result.files.single.path == null) return;
    try {
      final (file, error) =
          await _export.importAndVerify(result.files.single.path!);
      if (file == null) throw error ?? '校验失败';

      // 只展示备份中实际存在的模块
      final available = DataModule.presentIn(file.payload);
      if (available.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('备份中无可识别的数据模块')));
        return;
      }
      if (!context.mounted) return;
      final modules = await _pickBackupModules(context,
          title: '选择恢复内容', available: available);
      if (modules == null || modules.isEmpty) return;
      if (!context.mounted) return;

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('从备份恢复'),
          content: Text('将用备份中选中的 ${modules.length} 类数据替换当前对应数据，'
              '其它数据不受影响。此操作不可撤销。确认继续？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认恢复')),
          ],
        ),
      );
      if (ok != true) return;

      await _export.restoreBackup(file, modules: modules);
      if (!context.mounted) return;
      await context.read<QuestionBankProvider>().load();
      if (!context.mounted) return;
      await context.read<ReaderProvider>().load();
      if (!context.mounted) return;
      await context.read<PracticeExamProvider>().loadRulesAndResults();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已恢复选中的 ${modules.length} 类数据')));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('恢复失败：$e')));
      }
    }
  }

  /// 在系统资源管理器中打开当前数据存储文件夹（题库 db / 资料 / 笔记 / 附件所在）。
  Future<void> _openDataFolder() async {
    final root = await StorageConfig.dataRoot();
    final dir = Directory(root);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    try {
      await Process.start('explorer.exe', [root], mode: ProcessStartMode.detached);
    } catch (_) {
      // 非 Windows 或失败时回退：用 url_launcher（这里直接尝试 explorer 已够用）
    }
  }

  /// 更改数据存储位置：选择文件夹 -> 复制现有数据 -> 写入配置 -> 提示重启生效。
  Future<void> _changeDataLocation(BuildContext context) async {
    final current = await StorageConfig.dataRoot();
    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择数据存储位置',
      initialDirectory: current,
    );
    if (picked == null) return;
    if (picked == current) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已是当前存储位置')));
      }
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更改存储位置'),
        content: Text('将把全部数据复制到：\n$picked\n\n'
            '复制完成后需重启应用以在新位置运行。确认继续？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('复制并更改')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await StorageConfig.copyDataTo(picked);
      await StorageConfig.setDataRoot(picked);
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('完成'),
            content: Text('已复制 $n 个文件到新位置。\n请关闭并重新启动 StarHope 以生效。'),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('知道了')),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('更改失败：$e')));
      }
    }
  }

  /// 赞赏栏：跳转爱发电主页
  Widget _donateBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _openUrl('https://ifdian.net/a/ilovesl'),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary, cs.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.favorite, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('赞赏支持', style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
                  const SizedBox(height: 2),
                  Text('如果 StarHope 对你有帮助，请我喝杯咖啡 ☕',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.open_in_new, size: 18, color: cs.primary),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开失败：$e')));
      }
    }
  }

  Future<void> _logout(BuildContext context, AuthProvider auth) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后需重新输入密码登录。确认退出？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('退出')),
        ],
      ),
    );
    if (ok == true) auth.logout();
  }
}

// 引用常量
// ignore: unused_element
const String _kApp = AppConstants.appName;
