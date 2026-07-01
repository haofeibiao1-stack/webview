/// webview_bridge
///
/// 跨项目复用的 WebView + JSBridge 能力插件。
///
/// 分层：
/// - 传输层  [WebBridgeWebView]：承载 WebView、注册 channel、注入 Cookie/UA。
/// - 分发层  [BridgeDispatcher]：以 method 名分发到 Handler，替代巨型 switch。
/// - 能力层  [BridgeMethodHandler] 及内置实现：分享/保存/下载/账号/会员/埋点/UI。
/// - 宿主适配 [WebBridgeHostDelegate]：账号、会员、埋点、路由等 App 相关能力。
/// - UI 适配 [WebBridgeUiDelegate]：Loading 与 Toast 的展示。
///
/// 接入：`WebBridgeWebView(url: url, host: MyHostDelegate())`。
library;

export 'src/config/web_bridge_config.dart';
export 'src/core/bridge_context.dart';
export 'src/core/bridge_dispatcher.dart';
export 'src/core/bridge_method_handler.dart';
export 'src/delegate/host_delegate.dart';
export 'src/delegate/ui_delegate.dart';
export 'src/model/web_bridge_account.dart';
export 'src/model/webview_data.dart';
export 'src/widget/web_bridge_webview.dart';
