import 'dart:io';

import 'package:webview_flutter/webview_flutter.dart';

import '../config/web_bridge_config.dart';
import '../delegate/host_delegate.dart';
import '../model/web_bridge_account.dart';

/// 向 WebView 注入登录 Cookie。Android/鸿蒙需 URL 解码，iOS 用原值。
class CookieHelper {
  final WebBridgeHostDelegate host;
  final WebBridgeConfig config;

  const CookieHelper(this.host, this.config);

  Future<void> setCookie(
    WebViewController controller,
    WebViewCookieManager cookieManager, {
    String? path,
  }) async {
    try {
      final WebBridgeAccount? account = await host.getAccount();
      final q = account?.q ?? '';
      final t = account?.t ?? '';
      final qValue = !Platform.isIOS ? Uri.decodeComponent(q) : q;
      final tValue = !Platform.isIOS ? Uri.decodeComponent(t) : t;
      final url = path ?? (await controller.currentUrl() ?? '');
      final domain = Uri.parse(url).host;
      for (final name in config.qCookieNames) {
        await cookieManager.setCookie(
            WebViewCookie(name: name, value: qValue, domain: domain));
      }
      for (final name in config.tCookieNames) {
        await cookieManager.setCookie(
            WebViewCookie(name: name, value: tValue, domain: domain));
      }
    } catch (_) {}
  }
}
