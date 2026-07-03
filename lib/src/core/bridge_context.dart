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

  /// 本次消息是否已向 H5 回调名回过一次（供 [WebBridgeConfig.autoSuccessCallback]
  /// 判断是否需要补发统一成功回调，避免重复回调）。
  bool didCallback = false;

  BridgeContext({
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
    didCallback = true;
    controller.runJavaScript("$callback('$value')");
  }

  /// 以原始实参回调 H5：`callback(value)`（用于 bool/数字）。
  void callbackRaw(String callback, Object value) {
    if (callback.isEmpty) return;
    didCallback = true;
    controller.runJavaScript("$callback($value)");
  }

  /// 数据类回调：按 [WebBridgeConfig.callbackEnvelope] 决定输出格式。
  ///
  /// - 配置了 envelope（如文库）→ 输出包裹格式
  ///   `callback({error, msg, data})`；
  /// - 未配置（如 360AI 办公）→ 回退裸格式，与 [callbackString]/[callbackRaw]
  ///   字节级等价（String 走单引号，其余走原样），保证零回归。
  void emitResult(
    String callback, {
    int error = 0,
    String msg = 'success',
    Object? data,
  }) {
    if (callback.isEmpty) return;
    final envelope = config.callbackEnvelope;
    if (envelope != null) {
      didCallback = true;
      // 复刻原 webview：有数据才带 data 键，无数据方法只回 {error,msg}。
      final payload = <String, Object?>{'error': error, 'msg': msg};
      if (data != null) payload['data'] = data;
      controller.runJavaScript(envelope(callback, payload));
      return;
    }
    if (data is String) {
      callbackString(callback, data);
    } else {
      callbackRaw(callback, data ?? '');
    }
  }

  Future<void> setCookie({String? path}) =>
      cookieHelper.setCookie(controller, cookieManager, path: path);
}
