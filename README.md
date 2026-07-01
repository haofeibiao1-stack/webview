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

接入方需在原生侧声明：Android `READ_MEDIA_*` / `WRITE_EXTERNAL_STORAGE`（按版本），
iOS `NSPhotoLibraryAddUsageDescription`。
