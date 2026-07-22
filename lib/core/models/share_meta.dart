import '../constants.dart';

/// 分享者信息（.starhope 文件头部元数据）—— 核心层
///
/// 导出时由用户选择是否公开社交账号；仅昵称默认公开。
/// 导入时解析头部并弹出"分享者信息卡"。
class ShareMeta {
  final String authorId;
  final String nickname;

  /// 仅在作者公开时非空
  final String? github;
  final String? qq;
  final String? wechat;

  final String exportedAt;
  final ShareContentType contentType;

  /// 是否公开社交账号
  final bool publicSocial;

  const ShareMeta({
    required this.authorId,
    required this.nickname,
    this.github,
    this.qq,
    this.wechat,
    required this.exportedAt,
    required this.contentType,
    this.publicSocial = false,
  });

  Map<String, dynamic> toJson() => {
        'author_id': authorId,
        'nickname': nickname,
        if (publicSocial) ...{
          if (github != null) 'github': github,
          if (qq != null) 'qq': qq,
          if (wechat != null) 'wechat': wechat,
        },
        'exported_at': exportedAt,
        'content_type': contentType.name,
        'public_social': publicSocial,
        'app': AppConstants.appName,
        'format_version': AppConstants.formatVersion,
      };

  factory ShareMeta.fromJson(Map<String, dynamic> j) => ShareMeta(
        authorId: (j['author_id'] as String?) ?? '',
        nickname: (j['nickname'] as String?) ?? '未知',
        github: j['github'] as String?,
        qq: j['qq'] as String?,
        wechat: j['wechat'] as String?,
        exportedAt: (j['exported_at'] as String?) ?? '',
        contentType: ShareContentTypeX.fromName(j['content_type'] as String?),
        publicSocial: j['public_social'] as bool? ?? false,
      );

  String get displaySocial {
    final parts = <String>[];
    if (github != null && github!.isNotEmpty) parts.add('GitHub: $github');
    if (qq != null && qq!.isNotEmpty) parts.add('QQ: $qq');
    if (wechat != null && wechat!.isNotEmpty) parts.add('微信: $wechat');
    return parts.isEmpty ? '未公开' : parts.join('  ·  ');
  }
}
