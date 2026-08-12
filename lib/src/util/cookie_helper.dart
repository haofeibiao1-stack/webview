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
      final url = path ?? (await controller.currentUrl() ?? '');
      final cookies = await accountCookiesForUrl(url);
      for (final cookie in cookies) {
        await cookieManager.setCookie(cookie);
      }
    } catch (_) {}
  }

  /// 读取宿主当前账号，为目标 URL 生成账号 Cookie。
  ///
  /// Q/T 任一缺失都视为无有效账号，不写入空 Cookie，避免用空的子域 Cookie
  /// 覆盖或遮蔽父域有效登录态。
  Future<List<WebViewCookie>> accountCookiesForUrl(String url) async {
    final WebBridgeAccount? account = await host.getAccount();
    if (account == null || account.q.isEmpty || account.t.isEmpty) {
      return const [];
    }
    final domain = Uri.tryParse(url)?.host ?? '';
    if (domain.isEmpty) return const [];

    final qValue = !Platform.isIOS ? Uri.decodeComponent(account.q) : account.q;
    final tValue = !Platform.isIOS ? Uri.decodeComponent(account.t) : account.t;
    return [
      for (final name in config.qCookieNames)
        WebViewCookie(name: name, value: qValue, domain: domain),
      for (final name in config.tCookieNames)
        WebViewCookie(name: name, value: tValue, domain: domain),
    ];
  }
}
