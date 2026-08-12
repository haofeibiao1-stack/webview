import '../delegate/host_delegate.dart';
import 'account_cookie_host_policy.dart';

/// 首屏加载编排器：可信域账号 Cookie 预注入完成后才加载页面。
///
/// Cookie 校验或写入失败只会跳过预注入，不阻塞页面本身加载。
class AccountCookieBootstrapper {
  final bool enabled;
  final WebBridgeHostDelegate host;

  const AccountCookieBootstrapper({
    required this.enabled,
    required this.host,
  });

  Future<void> load({
    required String targetUrl,
    required Future<void> Function() seedCookie,
    required Future<void> Function() loadContent,
  }) async {
    if (enabled) {
      try {
        final target = Uri.tryParse(targetUrl);
        if (target != null &&
            target.host.isNotEmpty &&
            await AccountCookieHostPolicy.canSeed(host, target)) {
          await seedCookie();
        }
      } catch (_) {}
    }
    await loadContent();
  }
}
