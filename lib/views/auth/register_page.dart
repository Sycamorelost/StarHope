import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../common/glass.dart';
import '../common/starry_button.dart';
import '../common/theme.dart';
import '../common/window_title_bar.dart';

/// 首次启动强制注册页（账号/密码/昵称）
/// 社交账号在登录后于"我的-编辑资料"中设置。
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _account = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _nickname = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    _password2.dispose();
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().register(
            account: _account.text,
            password: _password.text,
            nickname: _nickname.text,
          );
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FrostedBackground(
        child: Column(
          children: [
            const WindowTitleBar(title: 'StarHope', showMaximize: false),
            Expanded(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: GlassCard(
                        padding: const EdgeInsets.all(28),
                        child: Form(
                          key: _formKey,
                          child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.auto_awesome,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 8),
                        Text('欢迎使用 StarHope',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('本地化学习助手 · 创建你的账户',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        const SizedBox(height: 24),
                        _field(_account, '账号', icon: Icons.person_outline,
                            validator: (v) {
                          if (v == null || v.trim().isEmpty) return '请输入账号';
                          if (v.trim().length < 3) return '账号至少 3 个字符';
                          return null;
                        }),
                        const SizedBox(height: 12),
                        _field(_nickname, '昵称', icon: Icons.badge_outlined,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? '请输入昵称' : null),
                        const SizedBox(height: 12),
                        _field(_password, '密码',
                            icon: Icons.lock_outline,
                            obscure: _obscure,
                            suffix: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                            validator: (v) {
                          if (v == null || v.isEmpty) return '请输入密码';
                          if (v.length < 6) return '密码至少 6 位';
                          return null;
                        }),
                        const SizedBox(height: 12),
                        _field(_password2, '确认密码',
                            icon: Icons.lock_outline, obscure: _obscure,
                            validator: (v) {
                          if (v != _password.text) return '两次密码不一致';
                          return null;
                        }),
                        const SizedBox(height: 24),
                        Text('社交账号可在登录后于「我的-编辑资料」中设置',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        const SizedBox(height: 24),
                        StarryButton(
                          label: _busy ? '创建中…' : '创建账户',
                          icon: Icons.rocket_launch_rounded,
                          onPressed: _busy ? null : _submit,
                        ),
                        const SizedBox(height: 16),
                        const PoweredFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {IconData? icon,
      bool obscure = false,
      Widget? suffix,
      String? Function(String?)? validator}) {
    return TextFormField(
      controller: c,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon) : null,
        suffixIcon: suffix,
      ),
      validator: validator,
    );
  }
}
