import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'media_capture_permission.dart';
import 'media_capture_system_permission.dart';

const _mediaPermissionLogTag = '【WebBridge-MediaPermission】';

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
    debugPrint(
      '$_mediaPermissionLogTag WebView权限回调进入 types=${request.types}',
    );
    final hasUnsupportedType = request.types.any(
      (type) =>
          type != WebViewPermissionResourceType.camera &&
          type != WebViewPermissionResourceType.microphone,
    );
    if (request.types.isEmpty || hasUnsupportedType) {
      debugPrint(
        '$_mediaPermissionLogTag WebView权限回调无法处理，直接 deny '
        'empty=${request.types.isEmpty} unsupported=$hasUnsupportedType '
        'types=${request.types}',
      );
      await request.deny();
      return;
    }

    final types = <WebBridgeMediaCaptureType>{
      if (request.types.contains(WebViewPermissionResourceType.camera))
        WebBridgeMediaCaptureType.camera,
      if (request.types.contains(WebViewPermissionResourceType.microphone))
        WebBridgeMediaCaptureType.microphone,
    };
    debugPrint(
      '$_mediaPermissionLogTag WebView权限回调已映射媒体类型 types=$types',
    );

    final result = await authorize(types);
    final isCurrentPageBeforeDecision = result.isCurrentPage;
    debugPrint(
      '$_mediaPermissionLogTag WebView授权结果 decision=${result.decision} '
      'showGuide=${result.shouldShowSettingsGuide} '
      'currentBeforeDecision=$isCurrentPageBeforeDecision '
      'permanent=${result.permanentlyDeniedTypes}',
    );
    if (result.isGranted && isCurrentPageBeforeDecision) {
      debugPrint('$_mediaPermissionLogTag WebView执行 grant');
      await request.grant();
    } else {
      debugPrint('$_mediaPermissionLogTag WebView执行 deny');
      await request.deny();
      final isCurrentPageAfterDeny = result.isCurrentPage;
      debugPrint(
        '$_mediaPermissionLogTag WebView deny完成 '
        'currentBeforeDecision=$isCurrentPageBeforeDecision '
        'currentAfterDeny=$isCurrentPageAfterDeny',
      );
      if (result.decision == MediaCapturePermissionDecision.permanentlyDenied &&
          result.shouldShowSettingsGuide &&
          isCurrentPageAfterDeny) {
        debugPrint('$_mediaPermissionLogTag 触发设置引导');
        await onPermanentlyDenied?.call(result.permanentlyDeniedTypes);
      }
    }
  }
}
