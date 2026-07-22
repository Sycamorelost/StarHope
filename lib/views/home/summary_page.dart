import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/ai_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_nav_provider.dart';
import '../../providers/practice_exam_provider.dart';
import '../../providers/question_provider.dart';
import '../../providers/reader_provider.dart';
import '../../services/file_storage_service.dart';
import '../common/glass.dart';
import '../common/user_avatar.dart';

/// 摘要主页：登录后默认首页，聚合用户信息与各模块数据概览；承担账号资料编辑。
class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key});
  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final qb = context.watch<QuestionBankProvider>();
    final pe = context.watch<PracticeExamProvider>();
    final ai = context.watch<AIProvider>();
    final user = auth.user;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // 用户卡片（头像可点换 + 刷新/编辑资料按钮）
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
                            color: cs.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.camera_alt,
                              size: 14, color: cs.onPrimary),
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
                      Text(user?.nickname ?? '用户',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('@${user?.account ?? ''}',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (user?.github != null && user!.github!.isNotEmpty)
                            _socialChip(Icons.code, 'GitHub: ${user.github}', cs),
                          if (user?.qq != null && user!.qq!.isNotEmpty)
                            _socialChip(Icons.chat, 'QQ: ${user.qq}', cs),
                          if (user?.wechat != null && user!.wechat!.isNotEmpty)
                            _socialChip(Icons.wechat_outlined,
                                '微信: ${user.wechat}', cs),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '刷新·全局同步数据',
                  onPressed: _refreshing ? null : _refreshAll,
                  icon: Icon(_refreshing ? Icons.sync : Icons.refresh,
                      color: cs.primary),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: '编辑资料',
                  onPressed: () => _editProfile(context, auth),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 4.5,
              children: [
                _statCard('题库题目', qb.questions.length,
                    Icons.library_books_outlined, cs.primary, cs),
                _statCard('题库文件夹', qb.folders.length,
                    Icons.folder_outlined, cs.tertiary, cs),
                _statCard('错题本', pe.wrongCount, Icons.error_outline,
                    Colors.red.shade400, cs),
                _statCard('AI 智能体', ai.agents.length,
                    Icons.smart_toy_outlined, cs.secondary, cs),
                _statCard('考试规则', pe.rules.length, Icons.school_outlined,
                    cs.primary, cs),
                _statCard('考试记录', pe.results.length,
                    Icons.assignment_turned_in_outlined, cs.tertiary, cs),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  // ===== 资料编辑（迁自 settings_page）=====
  Widget _socialChip(IconData icon, String text, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(text,
              style:
                  TextStyle(fontSize: 11, color: cs.onSecondaryContainer)),
        ],
      ),
    );
  }

  Future<String?> _pickAvatarFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: false,
      );
      if (result == null || result.files.single.path == null) return null;
      return await FileStorageService.saveAvatar(result.files.single.path!);
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

  Future<void> _editProfile(BuildContext context, AuthProvider auth) async {
    final user = auth.user!;
    final nickname = TextEditingController(text: user.nickname);
    final github = TextEditingController(text: user.github ?? '');
    final qq = TextEditingController(text: user.qq ?? '');
    final wechat = TextEditingController(text: user.wechat ?? '');
    final newPass = TextEditingController();
    final oldPass = TextEditingController();
    var avatarPath = user.avatarPath;

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
                            nickname: nickname.text.isEmpty
                                ? user.nickname
                                : nickname.text,
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
    if (saved != true) {
      nickname.dispose();
      github.dispose();
      qq.dispose();
      wechat.dispose();
      newPass.dispose();
      oldPass.dispose();
      return;
    }
    try {
      await auth.updateProfile(
        nickname: nickname.text,
        avatarPath: avatarPath,
        github: github.text,
        qq: qq.text,
        wechat: wechat.text,
        newPassword: newPass.text.isEmpty ? null : newPass.text,
        oldPassword: newPass.text.isEmpty ? null : oldPass.text,
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
    nickname.dispose();
    github.dispose();
    qq.dispose();
    wechat.dispose();
    newPass.dispose();
    oldPass.dispose();
  }

  // ===== 全局刷新（迁自 home_shell）=====
  Future<void> _refreshAll() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final qb = context.read<QuestionBankProvider>();
      final pe = context.read<PracticeExamProvider>();
      final rd = context.read<ReaderProvider>();
      final ai = context.read<AIProvider>();
      await Future.wait([
        qb.load(),
        pe.loadHistory(),
        pe.loadRulesAndResults(),
        rd.load(),
        ai.load(),
      ]);
      if (!mounted) return;
      context.read<HomeNavProvider>().bumpRefresh();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已刷新，数据已全局同步'), duration: Durations.short2));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Widget _statCard(
      String title, int count, IconData icon, Color color, ColorScheme cs) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
              child: Text(title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
          const SizedBox(width: 8),
          Text('$count',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
