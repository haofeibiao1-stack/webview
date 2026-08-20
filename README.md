# webview_bridge

跨项目复用的 **WebView + JSBridge 能力插件**。把「WebView 容器 + H5 桥能力」从
360AI 办公中抽离，其他 App（如 360 文库）只需提供一份宿主适配实现即可接入。

## 分层架构

```
传输层   WebBridgeWebView         承载 WebView、注册 channel、注入 Cookie/UA
分发层   BridgeDispatcher         按 method 名分发到 Handler（替代巨型 switch）
能力层   BridgeMethodHandler      分享/保存/下载/账号/会员/埋点/UI 等内置能力
宿主适配 WebBridgeHostDelegate    账号、会员、埋点、路由等 App 相关能力（接入方实现）
UI 适配  WebBridgeUiDelegate      Loading 与 Toast 展示（可用默认实现）
```

**自包含能力**（分享 `share`、保存相册 `savePhotoAndVideo`、下载 `downloadFile`、
`showToast`、Cookie 注入）由插件直接实现，不依赖宿主。**宿主相关能力**（登录、会员、
埋点、`funcJump`、`closePage` 等）通过 `WebBridgeHostDelegate` 反转依赖。

## H5 调用约定

```js
window.aiworkAppBridge.postMessage(JSON.stringify({ method, params, callback }));
```

## 接入步骤

1. 在宿主 `pubspec.yaml` 添加依赖：

```yaml
dependencies:
  webview_bridge:
    path: ../webview_bridge   # 或私有仓库版本号
```

2. 实现 `WebBridgeHostDelegate`，把接口映射到本项目的 `AppMethodChannel` / 全局能力：

```dart
class AiWorkHostDelegate extends WebBridgeHostDelegate {
  @override
  Future<WebBridgeAccount?> getAccount() async {
    final info = await AccountManager.accountInfo();
    return WebBridgeAccount(q: info?.q ?? '', t: info?.t ?? '');
  }

  @override
  Future<void> requestLogin() => AppMethodChannel.requestLogin();

  @override
  void funcJump(String jumpType, String path, String extra, String from,
          String funcId) =>
      globalJumpFunc?.call(jumpType, path, extra, from, funcId);

  @override
  void closePage() => globalRouter?.pop();

  @override
  void openFilePage() => AiWorkLib.openFilePage();

  @override
  void onFileSaved(String path) => globalPostSavePath?.call(path);

  // 账号/会员监听：把 AccountManager / MsPay 的回调转成 WebBridgeHostListener
  final _listeners = <WebBridgeHostListener>[];
  @override
  void addListener(WebBridgeHostListener l) => _listeners.add(l);
  @override
  void removeListener(WebBridgeHostListener l) => _listeners.remove(l);
  // ... 其余接口映射到 AppMethodChannel
}
```

3. 打开页面：

```dart
WebBridgeWebView(
  url: detailUrl,
  showTitle: true,
  host: AiWorkHostDelegate(),
  // 可选：定制 channel 名 / UA 标识 / Cookie 名 / 加载视图
  config: const WebBridgeConfig(
    channelName: 'aiworkAppBridge',
    uaMarker: '360ai办公',
  ),
  // 可选：接入方自定义 Loading / Toast 视觉
  // ui: MyUiDelegate(),
  // 可选：扩展宿主专属桥能力
  // extraHandlers: [MyCustomHandler()],
);
```

## H5 麦克风与摄像头权限

插件支持可信 H5 直接调用：

```js
await navigator.mediaDevices.getUserMedia({ audio: true });
await navigator.mediaDevices.getUserMedia({ video: true });
await navigator.mediaDevices.getUserMedia({ audio: true, video: true });
```

媒体采集权限默认关闭。宿主需要在配置中显式开启：

```dart
const WebBridgeConfig(
  enableMediaCapturePermission: true,
)
```

同时让宿主适配类额外实现 `WebBridgeMediaCapturePolicy`，复用宿主已有的可信域
策略。插件不会维护或复制域名白名单，每次收到 WebView 权限请求都会校验当前
顶层页面 URL；旧宿主无需修改已有 delegate 实现即可继续编译，但未实现策略接口
时媒体采集会默认拒绝：

```dart
class WenkuHostDelegate
    implements WebBridgeHostDelegate, WebBridgeMediaCapturePolicy {
  @override
  Future<bool> canRequestMediaCapture({
    required Uri url,
    required Set<WebBridgeMediaCaptureType> types,
  }) async {
    return UrlGuard.isTrustedWebUrl(url.toString());
  }
}
```

不可信页面、空 URL、非相机/麦克风资源、系统权限拒绝或处理异常都会返回拒绝，
H5 的 `getUserMedia()` Promise 将收到 `NotAllowedError`。由于
`webview_flutter` 的通用权限请求没有暴露 iframe 的真实请求源，包含跨域 iframe
的页面还应通过 HTTP `Permissions-Policy` 和 iframe `allow` 属性限制媒体权限。

权限请求到达时插件会同步保存当前顶层页面 URL 和导航代次；可信域检查或系统
授权期间一旦页面发生跳转（包括同 URL reload），旧请求会被拒绝，也不会与新
文档的请求合并。WebView 销毁时会使当前及排队请求全部失效，不再继续弹出权限框。

Android 11 及以上在用户多次拒绝后可能不再展示系统原生权限框。插件会区分普通
拒绝和永久拒绝：仍可申请时继续调用系统权限框；用户在本次系统框中拒绝并刚转为
永久拒绝时，不会紧接着叠加设置引导；后续 H5 再次申请才展示插件内引导弹窗，并
提供“去设置”入口。关闭引导后，下次点击仍可再次展示；从设置返回后会重新读取
权限状态，不缓存拒绝结果。

当 H5 同时请求摄像头和麦克风时，插件会按“摄像头 → 麦克风”的顺序逐项调用系统
权限请求；前一项请求完成后才会开始下一项，避免两个系统权限被合并到同一个弹窗。

平台限制：Android 可通过 WebView 权限回调执行上述策略；iOS 需要 iOS 15 及以上
的 `WKUIDelegate.requestMediaCapturePermissionFor` 回调，插件才能在 WebView 层
强制执行宿主可信域策略。iOS 14 及以下没有该委托能力，媒体请求仍可能进入 WebKit
自身的系统提示流程，插件无法承诺完全拦截；接入方不应把 iOS 14 视为已受本策略
完整保护。

## 扩展新能力

实现 `BridgeMethodHandler`，通过 `extraHandlers` 注册即可，无需改动分发逻辑：

```dart
class MyCustomHandler extends BridgeMethodHandler {
  @override
  Set<String> get methods => {'myMethod'};

  @override
  Future<void> handle(BridgeContext ctx, WebviewData data) async {
    // ctx.host / ctx.ui / ctx.controller / ctx.callbackString(...)
  }
}
```

## 内置桥方法

- 账号：`getCommonParams` `getExtraParams` `getAttribute` `getAccountParams`
  `requestLogin` `login` `requestLogout` `requestClearAccount` `jumpToUserInfo` `isLoggedIn`
- 会员：`isMemberShip` `getMemberInfo` `startMemberPage` `bindTourist`
  `isTouristMembership` `isTouristModeEnable` `refreshMember`
- 埋点/跳转：`onEvent` `manualActive` `funcJump`
- 媒体：`share`（链接/图片/视频，系统面板）`savePhotoAndVideo`（保存相册）
- 文件：`downloadFile`
- 页面：`showToast` `setCookie` `closePage`

> 注：图片/视频分享与保存等耗时操作会自动展示 Loading。

## 平台权限

保存相册能力需要接入方声明 Android `READ_MEDIA_*` / `WRITE_EXTERNAL_STORAGE`
（按版本）以及 iOS `NSPhotoLibraryAddUsageDescription`。

H5 媒体采集能力还需要宿主声明：

Android `AndroidManifest.xml`：

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

iOS `Info.plist`：

```xml
<key>NSCameraUsageDescription</key>
<string>需要访问您的摄像头</string>
<key>NSMicrophoneUsageDescription</key>
<string>需要访问您的麦克风</string>
```

iOS `Podfile` 中还需为 `permission_handler` 开启：

```ruby
"PERMISSION_CAMERA=1",
"PERMISSION_MICROPHONE=1",
```

远程 H5 应使用 HTTPS。
