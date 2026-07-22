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
import '../../services/export_service.dart';
import '../../services/file_storage_service.dart';
import '../../services/secure_storage_service.dart';
import '../../services/storage_config.dart';
import '../common/glass.dart';
import '../common/user_avatar.dart';
import '../common/disclaimer.dart';
import 'widgets/import_export_dialogs.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ExportService _export = ExportService();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = context.watch<ThemeProvider>();
    final user = auth.user;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('我的',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          // 用户卡片
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _pickAvatar(context, auth),
                  child: Stack(
                    children: [
                      UserAvatar(
                        avatarPath: user?.avatarPath,
                        nickname: user?.nickname ?? '',
                        radius: 32,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.camera_alt,
                              size: 14,
                              color: Theme.of(context).colorScheme.onPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.nickname ?? '',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('@${user?.account ?? ''}',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          if (user?.github != null &&
                              user!.github!.isNotEmpty)
                            _socialChip('GitHub', user.github!),
                          if (user?.qq != null && user!.qq!.isNotEmpty)
                            _socialChip('QQ', user.qq!),
                          if (user?.wechat != null &&
                              user!.wechat!.isNotEmpty)
                            _socialChip('微信', user.wechat!),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editProfile(context, auth),
                ),
              ],
            ),
          ),
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
            subtitle: '导出全部题目 / 资料 / 笔记 / 历史（不含 AI 密钥）',
            onTap: () => _fullBackup(context, auth),
          ),
          _menuTile(
            icon: Icons.restore_outlined,
            title: '从备份恢复',
            subtitle: '清空当前数据并从备份重建',
            onTap: () => _restore(context, auth),
          ),
          const SizedBox(height: 8),
          // 数据存储位置
          _sectionTitle('数据存储位置'),
          FutureBuilder<String>(
            future: StorageConfig.dataRoot(),
            builder: (_, snap) => _menuTile(
              icon: Icons.folder_open_outlined,
              title: '打开资源文件夹',
              subtitle: snap.data ?? '加载中…',
              onTap: () => _openDataFolder(),
            ),
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
            icon: Icons.lock_outline,
            title: '锁定热键',
            subtitle: '当前：${_hotkeyLabel(theme.lockHotkey)}（应用内按下即锁定回登录页）',
            onTap: () => _recordHotkey(context, theme),
          ),
          _menuTile(
            icon: Icons.delete_forever_outlined,
            title: '一键清空全部数据',
            subtitle: '清空题库/错题/历史/资料/AI 配置等所有本地数据并删除账户',
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('一键清空全部数据'),
        content: const Text(
            '将清空题库/错题/历史/资料/AI 配置等所有本地数据，并删除账户、注销回注册页。此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    final db = AppDatabase.instance;
    await db.clearAll();
    await db.deleteUser();
    await FileStorageService.clearAttachments();
    await SecureStorageService().clearAll();
    if (!context.mounted) return;
    auth.logout();
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

  Widget _socialChip(String k, String v) => Chip(
        label: Text('$k: $v', style: const TextStyle(fontSize: 11)),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );

  Future<String?> _pickAvatarFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: false,
      );
      if (result == null || result.files.single.path == null) return null;
      final newPath = await FileStorageService.saveAvatar(result.files.single.path!);
      return newPath;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return null;
    }
  }

  Future<void> _pickAvatar(BuildContext context, AuthProvider auth) async {
    final newPath = await _pickAvatarFile();
    if (newPath == null) return;
    await auth.updateProfile(avatarPath: newPath);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('头像已更新')));
    }
  }

  void _editProfile(BuildContext context, AuthProvider auth) async {
    final user = auth.user!;
    final nickname = TextEditingController(text: user.nickname);
    final github = TextEditingController(text: user.github ?? '');
    final qq = TextEditingController(text: user.qq ?? '');
    final wechat = TextEditingController(text: user.wechat ?? '');
    final newPass = TextEditingController();
    final oldPass = TextEditingController();
    String? avatarPath = user.avatarPath;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
        title: const Text('编辑资料'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final picked = await _pickAvatarFile();
                    if (picked != null) set(() => avatarPath = picked);
                  },
                  child: Stack(
                    children: [
                      UserAvatar(
                          avatarPath: avatarPath,
                          nickname: nickname.text.isEmpty ? user.nickname : nickname.text,
                          radius: 36),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Theme.of(ctx).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.camera_alt,
                              size: 14,
                              color: Theme.of(ctx).colorScheme.onPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text('点击更换头像（≤2MB）',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                TextField(
                    controller: nickname,
                    decoration: const InputDecoration(labelText: '昵称'),
                    onChanged: (_) => set(() {})),
                const SizedBox(height: 8),
                TextField(
                    controller: github,
                    decoration: const InputDecoration(labelText: 'GitHub')),
                const SizedBox(height: 8),
                TextField(
                    controller: qq,
                    decoration: const InputDecoration(labelText: 'QQ')),
                const SizedBox(height: 8),
                TextField(
                    controller: wechat,
                    decoration: const InputDecoration(labelText: '微信')),
                const Divider(),
                TextField(
                    controller: oldPass,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: '原密码（改密时填写）')),
                const SizedBox(height: 8),
                TextField(
                    controller: newPass,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: '新密码（留空则不改）')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
      ),
    );
    if (saved != true) return;

    try {
      await auth.updateProfile(
        nickname: nickname.text,
        avatarPath: avatarPath,
        github: github.text,
        qq: qq.text,
        wechat: wechat.text,
        newPassword:
            newPass.text.isEmpty ? null : newPass.text,
        oldPassword:
            oldPass.text.isEmpty ? null : oldPass.text,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('资料已更新')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  Future<Set<String>?> _pickBackupModules(BuildContext context) {
    final all = <(String, String, IconData)>[
      ('questions', '题库题目', Icons.library_books_outlined),
      ('folders', '题库文件夹', Icons.folder_outlined),
      ('practices', '练习历史', Icons.history),
      ('exam_rules', '考试规则', Icons.school_outlined),
      ('exam_results', '考试结果', Icons.assignment_turned_in_outlined),
      ('wrong', '错题本', Icons.error_outline),
      ('wrong_groups', '错题分组', Icons.label_outline),
      ('materials', '阅读资料与笔记', Icons.menu_book_outlined),
      ('ai_services', 'AI 服务配置（不含密钥）', Icons.cloud_outlined),
      ('ai_agents', 'AI 智能体', Icons.smart_toy_outlined),
      ('ai_conversations', 'AI 对话', Icons.chat_bubble_outline),
      ('ai_messages', 'AI 消息', Icons.message_outlined),
    ];
    final selected = <String>{for (final e in all) e.$1};
    return showDialog<Set<String>?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (sctx, set) => AlertDialog(
          title: const Text('选择备份内容'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in all)
                    CheckboxListTile(
                      dense: true,
                      value: selected.contains(e.$1),
                      onChanged: (v) => set(() {
                        if (v == true) {
                          selected.add(e.$1);
                        } else {
                          selected.remove(e.$1);
                        }
                      }),
                      secondary: Icon(e.$3, size: 20),
                      title: Text(e.$2),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从备份恢复'),
        content: const Text('此操作将清空当前全部数据并从备份重建，且不可撤销。确认继续？'),
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['starhope'],
    );
    if (result == null || result.files.single.path == null) return;
    try {
      final (file, error) =
          await _export.importAndVerify(result.files.single.path!);
      if (file == null) throw error ?? '校验失败';
      await _export.restoreBackup(file);
      if (!context.mounted) return;
      await context.read<QuestionBankProvider>().load();
      if (!context.mounted) return;
      await context.read<ReaderProvider>().load();
      if (!context.mounted) return;
      await context.read<PracticeExamProvider>().loadRulesAndResults();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('恢复完成')));
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
