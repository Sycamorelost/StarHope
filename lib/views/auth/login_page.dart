import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/user.dart';
import '../../providers/auth_provider.dart';
import '../common/earth_view.dart';
import '../common/glass.dart';
import '../common/starry_button.dart';
import '../common/starry_sky.dart';
import '../common/theme.dart';
import '../common/user_avatar.dart';
import '../common/window_title_bar.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _account = TextEditingController(); // 仅 fallback（无已注册用户时）使用
  final _password = TextEditingController();
  bool _obscure = true;
  bool _remember = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    // 优先用已注册账号；fallback 到 SecureStorage 记住的账号
    _account.text =
        auth.registeredUser?.account ?? auth.rememberedAccount ?? '';
  }

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final auth = context.read<AuthProvider>();
      // 已注册用户：账号取自 registeredUser；否则取输入框
      final account = auth.registeredUser?.account ?? _account.text;
      await auth.login(account, _password.text, remember: _remember);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 820;
    final cs = Theme.of(context).colorScheme;
    final ru = context.watch<AuthProvider>().registeredUser;
    return Scaffold(
      body: FrostedBackground(
        child: Column(
          children: [
            const WindowTitleBar(
              title: 'StarHope',
              showMaximize: false,
            ),
            Expanded(
              child: Stack(
                children: [
                  // 深蓝夜空渐变底（整页背景）
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF0b1026),
                            Color(0xFF141a3a),
                            Color(0xFF1a1140),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 流星星空（整页背景）
                  const Positioned.fill(
                    child: RepaintBoundary(
                      child: StarrySky(baseColor: Color(0xFF8ea2ff)),
                    ),
                  ),
                  // 右下角光晕
                  Positioned(
                    bottom: -80,
                    right: -60,
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                  // 内容层：宽屏 左地球 + 右登录（等高并排）；窄屏 仅登录卡居中
                  if (isWide)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 5,
                            child: RepaintBoundary(child: _earthPanel()),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 4,
                            child: Center(
                              child: SingleChildScrollView(
                                child: RepaintBoundary(
                                    child: _loginCard(context, ru)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Align(
                      alignment: Alignment.center,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: RepaintBoundary(child: _loginCard(context, ru)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 左侧动态地球毛玻璃面板（宽屏时与登录卡等高并排）
  Widget _earthPanel() {
    return GlassCard(
      surfaceColor: const Color(0xFF0b1026).withValues(alpha: 0.55),
      padding: EdgeInsets.zero,
      child: const EarthView(),
    );
  }

  /// 毛玻璃登录卡：已注册用户显示头像/昵称/@账号（账号只读展示），
  /// 密码为唯一输入框；无已注册用户时回退为账号+密码输入。
  Widget _loginCard(BuildContext context, User? ru) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: GlassCard(
        padding: const EdgeInsets.all(28),
        surfaceColor: Colors.white.withValues(alpha: 0.85),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ru != null) ...[
                Center(
                  child: UserAvatar(
                    avatarPath: ru.avatarPath,
                    nickname: ru.nickname,
                    radius: 48,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  ru.nickname,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '@${ru.account}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
              ] else ...[
                Text('欢迎回来',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface)),
                const SizedBox(height: 6),
                Text('登录你的 StarHope 账户',
                    style:
                        TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 28),
                _label('账号'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _account,
                  decoration: const InputDecoration(
                    hintText: '请输入账号',
                    prefixIcon: Icon(Icons.person_outline, size: 20),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入账号' : null,
                ),
                const SizedBox(height: 16),
              ],
              _label('密码'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  hintText: '请输入密码',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? '请输入密码' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('记住账号', style: TextStyle(fontSize: 13)),
                ],
              ),
              const SizedBox(height: 22),
              StarryButton(
                label: '登 录',
                icon: Icons.login_rounded,
                onPressed: _busy ? null : _submit,
              ),
              const SizedBox(height: 20),
              const Center(child: PoweredFooter()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500));
}
