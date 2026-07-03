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
