import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/ai_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/practice_exam_provider.dart';
import '../../providers/question_provider.dart';
import '../../providers/reader_provider.dart';
import '../common/starry_sky.dart';
import '../home/home_shell.dart';
import 'login_page.dart';
import 'register_page.dart';

/// 根据登录状态决定显示注册 / 登录 / 主界面
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isLoggedIn) {
      return auth.hasUser ? const LoginPage() : const RegisterPage();
    }
    // 登录后加载各模块数据并注入主密钥
    return const _PostLoginLoader(child: HomeShell());
  }
}

class _PostLoginLoader extends StatefulWidget {
  final Widget child;
  const _PostLoginLoader({required this.child});

  @override
  State<_PostLoginLoader> createState() => _PostLoginLoaderState();
}

class _PostLoginLoaderState extends State<_PostLoginLoader>
    with SingleTickerProviderStateMixin {
  bool _ready = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      final ai = context.read<AIProvider>();
      final qb = context.read<QuestionBankProvider>();
      final pe = context.read<PracticeExamProvider>();
      final rd = context.read<ReaderProvider>();
      // 注入主密钥给 AI 模块
      if (auth.masterKey != null) ai.injectMasterKey(auth.masterKey!);
      await Future.wait([
        ai.load(),
        qb.load(),
        pe.loadHistory(),
        pe.loadRulesAndResults(),
        rd.load(),
      ]);
      if (mounted) {
        _pulse.stop();
        setState(() => _ready = true);
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: _ready
          ? KeyedSubtree(
              key: const ValueKey('home'), child: widget.child)
          : KeyedSubtree(key: const ValueKey('loader'), child: _loader()),
    );
  }

  Widget _loader() {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          // 深蓝夜空渐变（整页背景）
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
          // 流星星空
          const Positioned.fill(
              child: RepaintBoundary(
                  child: StarrySky(baseColor: Color(0xFF8ea2ff)))),
          // 中央：脉冲品牌 + 文字 + 进度
          Center(
            child: RepaintBoundary(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: Tween(begin: 0.9, end: 1.12).animate(
                      CurvedAnimation(
                          parent: _pulse, curve: Curves.easeInOut),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            cs.primary,
                            cs.primary.withValues(alpha: 0.7)
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.5),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.auto_awesome,
                          size: 44, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('正在进入 StarHope…',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          letterSpacing: 1)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(
                          cs.primary.withValues(alpha: 0.9)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
