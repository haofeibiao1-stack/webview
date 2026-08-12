import '../delegate/host_delegate.dart';
import 'account_cookie_policy.dart';

/// 解析宿主可选的账号 Cookie 可信域策略；未实现或策略异常时安全拒绝。
abstract final class AccountCookieHostPolicy {
  static Future<bool> canSeed(
    WebBridgeHostDelegate host,
    Uri url,
  ) async {
    if (host is! WebBridgeCookiePolicy) return false;
    try {
      final policy = host as WebBridgeCookiePolicy;
      return await policy.canSeedAccountCookie(url);
    } catch (_) {
      return false;
    }
  }
}
