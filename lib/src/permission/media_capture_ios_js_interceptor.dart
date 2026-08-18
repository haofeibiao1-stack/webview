import 'dart:convert';

/// iOS WebKit 在用户拒绝媒体权限后，后续 getUserMedia 可能直接返回
/// NotAllowedError，而不再进入 WKUIDelegate。此拦截器在 H5 调用原始 API
/// 前先把请求交给 Flutter，由 Flutter 统一判断系统权限和设置引导。
abstract final class MediaCaptureIosJsInterceptor {
  static const responseHandlerName = '__webBridgeMediaPermissionRespond';

  /// 生成幂等的 getUserMedia 包装器。
  ///
  /// 包装器只负责保存原始 constraints、转发请求以及根据 Flutter 的结果
  /// resolve/reject Promise；可信域和系统权限判断仍由 Dart 侧完成。
  static String installationScript({required String channelName}) {
    final channelLiteral = jsonEncode(channelName);
    return '''
(function() {
  try {
    if (window.__webBridgeMediaCaptureShimInstalled) return;
    if (!navigator.mediaDevices ||
        typeof navigator.mediaDevices.getUserMedia !== 'function') {
      console.warn('[WebBridge-MediaPermission] getUserMedia unavailable');
      return;
    }

    var mediaDevices = navigator.mediaDevices;
    var originalGetUserMedia = navigator.mediaDevices.getUserMedia;
    var pending = Object.create(null);
    var sequence = 0;

    function makeError(name, message) {
      try {
        return new DOMException(message || 'Permission denied', name);
      } catch (_) {
        var error = new Error(message || 'Permission denied');
        error.name = name;
        return error;
      }
    }

    window.$responseHandlerName = function(rawResponse) {
      var response = rawResponse;
      try {
        if (typeof response === 'string') response = JSON.parse(response);
      } catch (_) {
        return;
      }
      if (!response || !response.requestId) return;

      var current = pending[response.requestId];
      if (!current) return;
      delete pending[response.requestId];

      if (response.granted === true) {
        Promise.resolve().then(function() {
          return originalGetUserMedia.call(mediaDevices, current.constraints);
        }).then(current.resolve, current.reject);
        return;
      }
      current.reject(makeError(
        response.errorName || 'NotAllowedError',
        response.errorMessage || 'Permission denied',
      ));
    };

    mediaDevices.getUserMedia = function(constraints) {
      var request = constraints || {};
      var needsAudio = !!request.audio;
      var needsVideo = !!request.video;
      if (!needsAudio && !needsVideo) {
        return Promise.reject(makeError(
          'TypeError',
          'At least one of audio or video must be requested',
        ));
      }

      var bridge = window[$channelLiteral];
      if (!bridge || typeof bridge.postMessage !== 'function') {
        return Promise.reject(makeError(
          'NotAllowedError',
          'Media permission bridge unavailable',
        ));
      }

      var requestId = 'media-' + Date.now() + '-' + (++sequence);
      return new Promise(function(resolve, reject) {
        pending[requestId] = {
          constraints: constraints,
          resolve: resolve,
          reject: reject,
        };
        try {
          bridge.postMessage(JSON.stringify({
            requestId: requestId,
            audio: needsAudio,
            video: needsVideo,
          }));
        } catch (error) {
          delete pending[requestId];
          reject(error);
        }
      });
    };

    mediaDevices.getUserMedia.__webBridgeOriginal = originalGetUserMedia;
    window.__webBridgeMediaCaptureShimInstalled = true;
    console.log('[WebBridge-MediaPermission] iOS getUserMedia shim installed');
  } catch (error) {
    console.error('[WebBridge-MediaPermission] iOS shim install failed', error);
  }
})();
''';
  }

  /// 生成 Flutter 回传给当前页面的 JS。
  static String responseScript({
    required String requestId,
    required bool granted,
    String decision = 'denied',
    bool showGuide = false,
  }) {
    final response = jsonEncode({
      'requestId': requestId,
      'granted': granted,
      'decision': decision,
      'showGuide': showGuide,
      'errorName': granted ? null : 'NotAllowedError',
      'errorMessage': granted ? null : 'Permission denied',
    });
    return 'window.$responseHandlerName($response);';
  }
}
