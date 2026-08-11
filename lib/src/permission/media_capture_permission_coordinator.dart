import 'dart:async';

import 'media_capture_permission.dart';
import 'media_capture_system_permission.dart';

typedef MediaCaptureUrlProvider = String? Function();
typedef MediaCaptureNavigationGenerationProvider = int Function();
typedef MediaCaptureTrustChecker = Future<bool> Function(
  Uri url,
  Set<WebBridgeMediaCaptureType> types,
);
typedef MediaCaptureSystemPermissionRequester
    = Future<MediaCapturePermissionResult> Function(
  Set<WebBridgeMediaCaptureType> types,
);

/// 串联功能开关、宿主可信域策略与系统媒体权限申请。
class MediaCapturePermissionCoordinator {
  final bool enabled;
  final MediaCaptureUrlProvider currentUrl;
  final MediaCaptureNavigationGenerationProvider currentNavigationGeneration;
  final MediaCaptureTrustChecker isTrusted;
  final MediaCaptureSystemPermissionRequester requestSystemPermissions;
  final Map<(Uri, int, String), Future<MediaCapturePermissionResult>>
      _inFlightRequests = {};
  final Map<WebBridgeMediaCaptureType, int>
      _settingsGuideSuppressedThroughSequence = {};
  Future<void> _requestQueue = Future<void>.value();
  int _lastEnqueuedRequestSequence = 0;
  bool _invalidated = false;

  MediaCapturePermissionCoordinator({
    required this.enabled,
    required this.currentUrl,
    required this.currentNavigationGeneration,
    required this.isTrusted,
    required this.requestSystemPermissions,
  });

  Future<MediaCapturePermissionResult> authorize(
    Set<WebBridgeMediaCaptureType> types,
  ) {
    if (!enabled || _invalidated || types.isEmpty) {
      return Future.value(const MediaCapturePermissionResult.denied());
    }

    final requestTypes = Set<WebBridgeMediaCaptureType>.unmodifiable(types);
    try {
      final url = _parseUrl(currentUrl());
      if (url == null) {
        return Future.value(const MediaCapturePermissionResult.denied());
      }
      final navigationGeneration = currentNavigationGeneration();
      return _enqueue(url, navigationGeneration, requestTypes);
    } catch (_) {
      return Future.value(const MediaCapturePermissionResult.denied());
    }
  }

  /// 使当前页面及队列中的权限请求全部失效，用于 WebView 销毁场景。
  void invalidate() {
    _invalidated = true;
  }

  Future<MediaCapturePermissionResult> _enqueue(
    Uri url,
    int navigationGeneration,
    Set<WebBridgeMediaCaptureType> requestTypes,
  ) {
    final typeKey = (requestTypes.toList()..sort((a, b) => a.index - b.index))
        .map((type) => type.name)
        .join(',');
    final key = (url, navigationGeneration, typeKey);
    final existing = _inFlightRequests[key];
    if (existing != null) return existing;

    final requestSequence = ++_lastEnqueuedRequestSequence;
    final completer = Completer<MediaCapturePermissionResult>();
    final request = completer.future;
    _inFlightRequests[key] = request;
    _requestQueue = _requestQueue.then((_) async {
      completer.complete(
        await _authorize(
          url,
          navigationGeneration,
          requestTypes,
          requestSequence,
        ),
      );
    });
    request.whenComplete(() {
      if (identical(_inFlightRequests[key], request)) {
        _inFlightRequests.remove(key);
      }
    });
    return request;
  }

  Future<MediaCapturePermissionResult> _authorize(
    Uri url,
    int navigationGeneration,
    Set<WebBridgeMediaCaptureType> types,
    int requestSequence,
  ) async {
    try {
      if (!_isCurrentPage(url, navigationGeneration)) {
        return const MediaCapturePermissionResult.denied();
      }
      if (!await isTrusted(url, types)) {
        return const MediaCapturePermissionResult.denied();
      }
      if (!_isCurrentPage(url, navigationGeneration)) {
        return const MediaCapturePermissionResult.denied();
      }
      var result = await requestSystemPermissions(types);
      if (!_isCurrentPage(url, navigationGeneration)) {
        return const MediaCapturePermissionResult.denied();
      }
      if (result.decision == MediaCapturePermissionDecision.permanentlyDenied) {
        if (result.shouldShowSettingsGuide) {
          final hasGuideEligibleType = result.permanentlyDeniedTypes.any(
            (type) =>
                requestSequence >
                (_settingsGuideSuppressedThroughSequence[type] ?? 0),
          );
          if (!hasGuideEligibleType) {
            result = result.withSettingsGuideVisibility(false);
          }
        } else {
          for (final type in result.permanentlyDeniedTypes) {
            _settingsGuideSuppressedThroughSequence[type] =
                _lastEnqueuedRequestSequence;
          }
        }
      }
      return result.withCurrentPageValidator(
        () => _isCurrentPage(url, navigationGeneration),
      );
    } catch (_) {
      return const MediaCapturePermissionResult.denied();
    }
  }

  bool _isCurrentPage(Uri expectedUrl, int expectedGeneration) {
    return !_invalidated &&
        currentNavigationGeneration() == expectedGeneration &&
        _parseUrl(currentUrl()) == expectedUrl;
  }

  Uri? _parseUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    final url = Uri.tryParse(rawUrl.trim());
    if (url == null || !url.hasScheme || url.host.isEmpty) return null;
    return url;
  }
}
