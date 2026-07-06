import 'package:flutter/widgets.dart';

/// 回调封装器：把「回调名 + 载荷」转换为最终执行的 JS 表达式。
///
/// 为空时插件回退裸格式（`cb('value')` / `cb(value)`，360AI 办公在用）。
/// 文库存量 H5 期望包裹格式，可传
/// `(name, payload) => "$name(${jsonEncode(payload)})"`，
/// 由 [BridgeContext.emitResult] 组装 `{error, msg, data}` 载荷。
typedef CallbackEnvelope = String Function(String name, Object? payload);

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

  /// 数据类回调的封装器。为空则用裸格式回调（向后兼容 360AI 办公）；
  /// 非空则 [BridgeContext.emitResult] 用它输出包裹格式（文库存量 H5）。
  final CallbackEnvelope? callbackEnvelope;

  /// iOS 是否允许内联播放（`allowsInlineMediaPlayback`）。默认 false，
  /// 保持 webview_flutter 默认（360AI 办公不受影响）；承载视频 H5 的宿主可开启。
  final bool enableInlineMediaPlayback;

  /// 媒体是否可自动播放（无需用户手势）。默认 false，保持平台默认；
  /// 开启后 iOS 清空 `mediaTypesRequiringUserAction`、Android
  /// `setMediaPlaybackRequiresUserGesture(false)`。
  final bool mediaAutoPlay;

  /// `requestLogin`/`login` 是否加「已登录则跳过」守卫。默认 false（360AI 办公
  /// 无条件触发登录）；文库存量逻辑仅在未登录时登录，置 true 复刻。
  final bool guardRequestLogin;

  /// 是否对每条带回调名的消息补发统一成功回调 `cb({error:0,msg:'success',...})`。
  /// 默认 false（360AI 办公按 Handler 各自决定）；文库存量 H5 依赖「无论何种
  /// 方法都回一次成功」，置 true 复刻——已回过数据的方法不重复回调。
  final bool autoSuccessCallback;

  /// 是否注册 `Toaster` JSBridge 通道（H5 postMessage 弹 SnackBar）。默认 false；
  /// 文库存量 H5 用到，置 true 复刻。
  final bool enableToaster;

  /// 是否开启 WebView 调试（Android `enableDebugging`、iOS 非 release
  /// `setInspectable`）。默认 false；文库存量置 true 复刻。
  final bool enableWebDebugging;

  /// WebView 背景色。为空则不设置（保持默认）；文库存量用透明
  /// `Color(0x00000000)`。
  final Color? backgroundColor;

  /// 非内嵌 Scaffold 是否仅在非 iOS 上 resize 以避让键盘（iOS 置 false，
  /// 规避 WPS 网页因 resize 收起输入法）。默认 false（保持 Scaffold 默认）；
  /// 文库存量独立页置 true 复刻。
  final bool avoidBottomInsetExceptIOS;

  /// Android 上是否在页面加载完成后注入阻止 `img` 拖拽的 JS。默认 true（保持
  /// 插件既有行为，360AI 办公不受影响）；文库原 `webview.dart` 无此注入，置
  /// false 复刻。
  final bool preventAndroidImageDrag;

  /// 加载失败时是否用失败视图替换 WebView。默认 true（保持插件既有行为，
  /// 360AI 办公不受影响）；文库原 `webview.dart` 加载失败仅打日志、始终保留
  /// WebView，置 false 复刻。
  final bool showLoadFailView;

  /// 需要在 `window.<channelName>` 上注入具名函数的运营能力方法名。
  ///
  /// JavaScriptChannel 原生只在 channel 对象上挂 `postMessage`，H5 无法用
  /// `typeof window.<channelName>.login === 'function'` 探测某能力是否可用。
  /// 本列表里的方法会被注入为真实函数（转发到 `postMessage`），使 H5 能按
  /// 「属性是否存在」判断接口可用性，与原生端行为一致。
  ///
  /// 默认注入 `login` / `share` / `savePhotoAndVideo`（360AI 办公与文库运营
  /// H5 共用的三个运营能力）；传空列表则不注入任何 shim。
  final List<String> operationalShimMethods;

  /// 是否在 `onPageStarted`（页面开始加载）时自动注入一次 Cookie。
  ///
  /// 默认 true，复刻 360AI 办公老代码：为规避鸿蒙平台「控制器/WebView 未注册好
  /// 导致 Cookie 注入失败」，办公特意把注入时机放到 onPageStarted（提交
  /// `afda7ef`）。文库老代码 onPageStarted 不种 Cookie，仅在登录/登出监听与
  /// H5 `requestLogin` 时种，置 false 复刻——未登录打开页面也不会种入游客串。
  final bool seedCookieOnPageStarted;

  const WebBridgeConfig({
    this.channelName = 'aiworkAppBridge',
    this.uaMarker = '360aiwork',
    this.qCookieNames = const ['Q', '__NS_Q'],
    this.tCookieNames = const ['T', '__NS_T'],
    this.loadFailBuilder,
    this.callbackEnvelope,
    this.enableInlineMediaPlayback = false,
    this.mediaAutoPlay = false,
    this.guardRequestLogin = false,
    this.autoSuccessCallback = false,
    this.enableToaster = false,
    this.enableWebDebugging = false,
    this.backgroundColor,
    this.avoidBottomInsetExceptIOS = false,
    this.preventAndroidImageDrag = true,
    this.showLoadFailView = true,
    this.operationalShimMethods = const ['login', 'share', 'savePhotoAndVideo'],
    this.seedCookieOnPageStarted = true,
  });
}
