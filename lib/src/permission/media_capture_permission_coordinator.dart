import 'dart:async';

import 'package:flutter/foundation.dart';

import 'media_capture_permission.dart';
import 'media_capture_system_permission.dart';

const _mediaPermissionLogTag = '【WebBridge-MediaPermission】';

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
    debugPrint(
      '$_mediaPermissionLogTag 协调器收到请求 types=$types enabled=$enabled invalidated=$_invalidated',
    );
    if (!enabled || _invalidated || types.isEmpty) {
      return Future.value(const MediaCapturePermissionResult.denied());
    }

    final requestTypes = Set<WebBridgeMediaCaptureType>.unmodifiable(types);
    try {
      final rawUrl = currentUrl();
      final url = _parseUrl(rawUrl);
      if (url == null) {
        debugPrint(
          '$_mediaPermissionLogTag 请求被拒绝：当前 URL 无效 rawUrl=$rawUrl',
        );
        return Future.value(const MediaCapturePermissionResult.denied());
      }
      final navigationGeneration = currentNavigationGeneration();
      debugPrint(
        '$_mediaPermissionLogTag 请求入队 url=$url generation=$navigationGeneration types=$requestTypes',
      );
      return _enqueue(url, navigationGeneration, requestTypes);
    } catch (_) {
      debugPrint('$_mediaPermissionLogTag 请求入队前检查异常，按拒绝处理');
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
    if (existing != null) {
      debugPrint(
        '$_mediaPermissionLogTag 复用进行中的权限请求 '
        'url=$url generation=$navigationGeneration types=$requestTypes',
      );
      return existing;
    }

    final requestSequence = ++_lastEnqueuedRequestSequence;
    final completer = Completer<MediaCapturePermissionResult>();
    final request = completer.future;
    _inFlightRequests[key] = request;
    debugPrint(
      '$_mediaPermissionLogTag 创建权限请求 sequence=$requestSequence '
      'url=$url generation=$navigationGeneration types=$requestTypes '
      'queueSize=${_inFlightRequests.length}',
    );
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
      debugPrint(
        '$_mediaPermissionLogTag 开始执行权限请求 sequence=$requestSequence '
        'url=$url generation=$navigationGeneration types=$types '
        'currentUrl=${currentUrl() ?? '<null>'} '
        'currentGeneration=${currentNavigationGeneration()}',
      );
      if (!_isCurrentPage(url, navigationGeneration)) {
        debugPrint(
          '$_mediaPermissionLogTag 权限请求执行前页面已变化 sequence=$requestSequence',
        );
        return const MediaCapturePermissionResult.denied();
      }
      final trusted = await isTrusted(url, types);
      debugPrint(
        '$_mediaPermissionLogTag 可信域检查结果 sequence=$requestSequence '
        'url=$url types=$types trusted=$trusted',
      );
      if (!trusted) {
        return const MediaCapturePermissionResult.denied();
      }
      if (!_isCurrentPage(url, navigationGeneration)) {
        debugPrint(
          '$_mediaPermissionLogTag 可信域检查后页面已变化 sequence=$requestSequence',
        );
        return const MediaCapturePermissionResult.denied();
      }
      debugPrint(
        '$_mediaPermissionLogTag 开始调用系统权限请求器 '
        'sequence=$requestSequence types=$types',
      );
      var result = await requestSystemPermissions(types);
      debugPrint(
        '$_mediaPermissionLogTag 系统权限结果 sequence=$requestSequence decision=${result.decision} '
        'permanent=${result.permanentlyDeniedTypes} showGuide=${result.shouldShowSettingsGuide}',
      );
      if (!_isCurrentPage(url, navigationGeneration)) {
        debugPrint(
          '$_mediaPermissionLogTag 系统权限结果返回后页面已变化 '
          'sequence=$requestSequence',
        );
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
            debugPrint(
              '$_mediaPermissionLogTag 引导被排队抑制 sequence=$requestSequence '
              'suppressed=$_settingsGuideSuppressedThroughSequence',
            );
            result = result.withSettingsGuideVisibility(false);
          }
        } else {
          for (final type in result.permanentlyDeniedTypes) {
            _settingsGuideSuppressedThroughSequence[type] =
                _lastEnqueuedRequestSequence;
          }
          debugPrint(
            '$_mediaPermissionLogTag 记录本次拒绝抑制范围 sequence=$requestSequence '
            'through=$_lastEnqueuedRequestSequence types=${result.permanentlyDeniedTypes}',
          );
        }
      }
      final finalResult = result.withCurrentPageValidator(
        () => _isCurrentPage(url, navigationGeneration),
      );
      debugPrint(
        '$_mediaPermissionLogTag 权限请求执行结束 sequence=$requestSequence '
        'decision=${finalResult.decision} '
        'showGuide=${finalResult.shouldShowSettingsGuide} '
        'permanent=${finalResult.permanentlyDeniedTypes}',
      );
      return finalResult;
    } catch (error, stackTrace) {
      debugPrint(
        '$_mediaPermissionLogTag 权限请求执行异常 '
        'sequence=$requestSequence url=$url types=$types error=$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      return const MediaCapturePermissionResult.denied();
    }
  }

  bool _isCurrentPage(Uri expectedUrl, int expectedGeneration) {
    final actualUrl = _parseUrl(currentUrl());
    final actualGeneration = currentNavigationGeneration();
    final valid = !_invalidated &&
        actualGeneration == expectedGeneration &&
        actualUrl == expectedUrl;
    if (!valid) {
      debugPrint(
        '$_mediaPermissionLogTag 页面校验失败 '
        'expectedUrl=$expectedUrl actualUrl=${actualUrl ?? '<null>'} '
        'expectedGeneration=$expectedGeneration actualGeneration=$actualGeneration '
        'invalidated=$_invalidated',
      );
    }
    return valid;
  }

  Uri? _parseUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    final url = Uri.tryParse(rawUrl.trim());
    if (url == null || !url.hasScheme || url.host.isEmpty) return null;
    return url;
  }
}
