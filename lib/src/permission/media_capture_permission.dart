/// H5 通过 `getUserMedia()` 可申请的媒体采集资源。
enum WebBridgeMediaCaptureType {
  camera,
  microphone,
}

/// 可选的媒体采集可信域策略。
///
/// 宿主按需实现此接口并复用自身白名单；未实现的宿主默认拒绝媒体采集，且不会因
/// WebBridgeHostDelegate 增加成员而破坏既有 `implements` 接入方式。
abstract interface class WebBridgeMediaCapturePolicy {
  Future<bool> canRequestMediaCapture({
    required Uri url,
    required Set<WebBridgeMediaCaptureType> types,
  });
}
