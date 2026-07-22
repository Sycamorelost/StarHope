/// 本地单账户用户模型 —— 核心层
///
/// 密码经 PBKDF2 加盐哈希存储；主密码用于敏感操作二次验证与
/// 派生 AES-GCM 密钥（保护 AI API Key 等敏感数据）。
class User {
  final String id;
  final String account;
  final String nickname;

  /// PBKDF2 输出（hex），与 [salt] 绑定
  final String passwordHash;

  /// 盐值（hex），随机生成
  final String salt;

  final String? avatarPath;
  final String? github;
  final String? qq;
  final String? wechat;
  final int createdAt;

  User({
    required this.id,
    required this.account,
    required this.nickname,
    required this.passwordHash,
    required this.salt,
    this.avatarPath,
    this.github,
    this.qq,
    this.wechat,
    required this.createdAt,
  });

  Map<String, dynamic> toRow() => {
        'id': id,
        'account': account,
        'nickname': nickname,
        'password_hash': passwordHash,
        'salt': salt,
        'avatar_path': avatarPath ?? '',
        'github': github ?? '',
        'qq': qq ?? '',
        'wechat': wechat ?? '',
        'created_at': createdAt,
      };

  factory User.fromRow(Map<String, dynamic> r) => User(
        id: r['id'] as String,
        account: (r['account'] as String?) ?? '',
        nickname: (r['nickname'] as String?) ?? '',
        passwordHash: (r['password_hash'] as String?) ?? '',
        salt: (r['salt'] as String?) ?? '',
        avatarPath: _nbe(r['avatar_path']),
        github: _nbe(r['github']),
        qq: _nbe(r['qq']),
        wechat: _nbe(r['wechat']),
        createdAt: (r['created_at'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'account': account,
        'nickname': nickname,
        'avatar_path': avatarPath,
        'github': github,
        'qq': qq,
        'wechat': wechat,
        'created_at': createdAt,
      };
  // 注意：导出公开信息时不含 passwordHash / salt

  User copyWith({
    String? nickname,
    String? avatarPath,
    String? github,
    String? qq,
    String? wechat,
    String? passwordHash,
    String? salt,
  }) =>
      User(
        id: id,
        account: account,
        nickname: nickname ?? this.nickname,
        passwordHash: passwordHash ?? this.passwordHash,
        salt: salt ?? this.salt,
        avatarPath: avatarPath ?? this.avatarPath,
        github: github ?? this.github,
        qq: qq ?? this.qq,
        wechat: wechat ?? this.wechat,
        createdAt: createdAt,
      );
}

String? _nbe(Object? v) {
  final s = v?.toString();
  if (s == null || s.isEmpty) return null;
  return s;
}

/// 工具：将社交账号序列化为紧凑串
String encodeSocial({String? github, String? qq, String? wechat}) {
  final parts = <String>[];
  if (github != null && github.isNotEmpty) parts.add('github:$github');
  if (qq != null && qq.isNotEmpty) parts.add('qq:$qq');
  if (wechat != null && wechat.isNotEmpty) parts.add('wechat:$wechat');
  return parts.join(';');
}

Map<String, String> decodeSocial(String? s) {
  final out = <String, String>{};
  if (s == null || s.isEmpty) return out;
  for (final part in s.split(';')) {
    final idx = part.indexOf(':');
    if (idx > 0) out[part.substring(0, idx)] = part.substring(idx + 1);
  }
  return out;
}
