import 'package:flutter/widgets.dart';

/// 插件接入配置。不同宿主 App 可定制 channel 名、UA 标识、Cookie 名与占位视图。
class WebBridgeConfig {
  /// JavaScriptChannel 名称，H5 通过 `window.<channelName>.postMessage` 调用。
  final String channelName;

  /// 追加到 UA 末尾的宿主标识，服务端据此区分客户端。为空则不注入。
  final String uaMarker;

  /// 写入 q 值的 Cookie 名列表。
  final List<String> qCookieNames;

  /// 写入 t 值的 Cookie 名列表。
  final List<String> tCookieNames;

  /// 页面加载失败视图构造器，为空则用内置默认视图。
  final Widget Function(BuildContext context, Future<void> Function() retry)?
      loadFailBuilder;

  const WebBridgeConfig({
    this.channelName = 'aiworkAppBridge',
    this.uaMarker = '360ai办公',
    this.qCookieNames = const ['Q', '__NS_Q'],
    this.tCookieNames = const ['T', '__NS_T'],
    this.loadFailBuilder,
  });
}
