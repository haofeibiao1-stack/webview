import 'package:webview_flutter/webview_flutter.dart';

import 'media_capture_permission.dart';
import 'media_capture_system_permission.dart';

typedef MediaCaptureAuthorizer = Future<MediaCapturePermissionResult> Function(
  Set<WebBridgeMediaCaptureType> types,
);
typedef MediaCapturePermanentlyDeniedHandler = Future<void> Function(
  Set<WebBridgeMediaCaptureType> types,
);

/// 把 webview_flutter 的平台权限请求转换为插件内部媒体采集类型。
class MediaCaptureWebViewPermissionHandler {
  final MediaCaptureAuthorizer authorize;
  final MediaCapturePermanentlyDeniedHandler? onPermanentlyDenied;

  const MediaCaptureWebViewPermissionHandler({
    required this.authorize,
    this.onPermanentlyDenied,
  });

  Future<void> handle(PlatformWebViewPermissionRequest request) async {
    final hasUnsupportedType = request.types.any(
      (type) =>
          type != WebViewPermissionResourceType.camera &&
          type != WebViewPermissionResourceType.microphone,
    );
    if (request.types.isEmpty || hasUnsupportedType) {
      await request.deny();
      return;
    }

    final types = <WebBridgeMediaCaptureType>{
      if (request.types.contains(WebViewPermissionResourceType.camera))
        WebBridgeMediaCaptureType.camera,
      if (request.types.contains(WebViewPermissionResourceType.microphone))
        WebBridgeMediaCaptureType.microphone,
    };

    final result = await authorize(types);
    if (result.isGranted && result.isCurrentPage) {
      await request.grant();
    } else {
      await request.deny();
      if (result.decision == MediaCapturePermissionDecision.permanentlyDenied &&
          result.shouldShowSettingsGuide &&
          result.isCurrentPage) {
        await onPermanentlyDenied?.call(result.permanentlyDeniedTypes);
      }
    }
  }
}
