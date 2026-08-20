import 'package:webview_flutter/webview_flutter.dart';

/// WebView Cookie 清理入口。中立于任何账号体系:插件只提供「清理」这个动作,
/// 由宿主在合适的时机(通常是账号登出)调用,宿主自己决定何时触发。
///
/// 为什么是「清空全部」而不是「只删账号 Cookie」:
/// webview_flutter 的 Cookie 能力只有 [WebViewCookieManager.clearCookies]
/// (清全部)和 [WebViewCookieManager.setCookie](加/覆盖)。而 [WebViewCookie]
/// 只有 name/value/domain/path,没有 expires/maxAge 字段,无法让某个具名 Cookie
/// 过期删除。因此纯 Dart 层做不到「只删 Q/T」,只能整体清空。登出本就应让整个
/// 会话失效,清空 WebView 全部 Cookie 通常可接受(iOS 文库端亦是同样做法)。
class WebBridgeCookieCleaner {
  const WebBridgeCookieCleaner._();

  /// 清空所有 WebView 的全部 Cookie。失败静默,不抛给调用方。
  ///
  /// 返回清理前是否存在 Cookie(透传 [WebViewCookieManager.clearCookies]);
  /// 异常时返回 false。
  static Future<bool> clearAll() async {
    try {
      return await WebViewCookieManager().clearCookies();
    } catch (_) {
      return false;
    }
  }
}
