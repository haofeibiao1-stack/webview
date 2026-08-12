/// 宿主可选实现的账号 Cookie 可信域策略。
///
/// 插件只会在宿主明确允许的目标地址上执行首屏账号 Cookie 预注入；未实现本接口
/// 的旧宿主默认拒绝，避免插件升级后向任意 H5 暴露登录凭证。
abstract interface class WebBridgeCookiePolicy {
  Future<bool> canSeedAccountCookie(Uri url);
}
