import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/web_bridge_config.dart';
import '../delegate/host_delegate.dart';
import '../delegate/ui_delegate.dart';
import '../util/cookie_helper.dart';

/// 传递给每个 Handler 的运行时上下文，聚合 WebView 控制器与各适配层。
class BridgeContext {
  final BuildContext buildContext;
  final WebViewController controller;
  final WebViewCookieManager cookieManager;
  final WebBridgeHostDelegate host;
  final WebBridgeUiDelegate ui;
  final WebBridgeConfig config;
  final CookieHelper cookieHelper;

  const BridgeContext({
    required this.buildContext,
    required this.controller,
    required this.cookieManager,
    required this.host,
    required this.ui,
    required this.config,
    required this.cookieHelper,
  });

  bool get mounted => buildContext.mounted;

  /// 执行任意 JS。
  void runJs(String js) => controller.runJavaScript(js);

  /// 以字符串实参回调 H5：`callback('value')`。
  void callbackString(String callback, String value) {
    if (callback.isEmpty) return;
    controller.runJavaScript("$callback('$value')");
  }

  /// 以原始实参回调 H5：`callback(value)`（用于 bool/数字）。
  void callbackRaw(String callback, Object value) {
    if (callback.isEmpty) return;
    controller.runJavaScript("$callback($value)");
  }

  Future<void> setCookie({String? path}) =>
      cookieHelper.setCookie(controller, cookieManager, path: path);
}
