import '../delegate/host_delegate.dart';
import 'media_capture_permission.dart';

/// 解析宿主可选的媒体采集策略；未实现策略接口时安全拒绝。
abstract final class MediaCaptureHostPolicy {
  static Future<bool> isTrusted(
    WebBridgeHostDelegate host, {
    required Uri url,
    required Set<WebBridgeMediaCaptureType> types,
  }) {
    if (host is! WebBridgeMediaCapturePolicy) {
      return Future<bool>.value(false);
    }
    final policy = host as WebBridgeMediaCapturePolicy;
    return policy.canRequestMediaCapture(url: url, types: types);
  }
}
