## 0.0.7

* iOS 保存图片/视频到相册前先受控申请相册权限（`Permission.photos`，对应宿主 Podfile 的 `PERMISSION_PHOTOS=1` 与 Info.plist 的 `NSPhotoLibraryUsageDescription`）；`granted`/`limited` 均可写入，被拒时提示「未获得相册权限」并中止，避免 `image_gallery_saver_plus` 因缺权限在写入时直接失败。新增 `permission_handler` 依赖。

## 0.0.6

* `WebBridgeConfig` 新增 `seedCookieOnPageStarted`（默认 true）：控制 `onPageStarted` 页面加载时是否自动注入一次 Cookie。默认复刻 360AI 办公老代码（为规避鸿蒙控制器/WebView 未注册好导致注入失败，办公特意把种 Cookie 时机放在 onPageStarted，提交 `afda7ef`）；文库老代码 onPageStarted 不种 Cookie，文库 config 置 false 复刻，未登录打开页面不再种入账号 SDK 游客串（`qid=V...&uidvm=true`）。登录/登出监听与 H5 主动登录路径行为不变。

## 0.0.5

* 修复运营能力 `login`：已登录点击 login 无反应。拆分 `login` 与 `requestLogin`——`login` 已登录时跳转个人信息页(`jumpToUserInfo`)、未登录才拉起登录并种 Cookie;`requestLogin` 维持登录态守卫语义不变。

## 0.0.4

* 增加文库存量 H5 兼容配置,通过 `WebBridgeConfig` 新增可选开关(默认保持既有行为,360AI 办公零回归)。
* `BridgeContext` 新增 `emitResult`,按 envelope 决定裸格式/包裹格式(裸格式与原回调字节级等价)。
* `WebBridgeWebView` 支持 embedded/showLoading、controller 及生命周期回调、onMessage 兜底、本地 asset 加载、文件选择器转发。
* `host_delegate` 新增去平台化的 `onShowFileSelector`;导出 `WebViewController`。

## 0.0.2

* WebviewData.fromJson 兼容 `type` 字段回退(优先 `method`,回退 `type`)。
* pubspec 补充 homepage/repository 元信息。

## 0.0.1

* TODO: Describe initial release.
