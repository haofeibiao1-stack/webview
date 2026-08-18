import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'media_capture_permission.dart';

const _mediaPermissionLogTag = '【WebBridge-MediaPermission】';

/// 平台原生媒体权限委托支持设置引导的目标平台。
///
/// WebView 的媒体权限回调仅在 Android 和 iOS 有对应实现；其他平台不应尝试
/// 展示面向移动端系统设置的引导。
bool supportsMediaCapturePermissionGuide(TargetPlatform platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.iOS;

typedef MediaCapturePermissionGuidePresenter = Future<void> Function();
typedef OpenMediaCaptureAppSettings = Future<bool> Function();
typedef CanPresentMediaCapturePermissionGuide = bool Function();
typedef PresentMediaCapturePermissionGuide = Future<void> Function(
  Set<WebBridgeMediaCaptureType> types,
);

/// 合并同时到达的永久拒绝引导，并允许弹窗关闭后的下一次请求重新展示。
class MediaCapturePermissionGuideController {
  Future<void>? _inFlight;

  Future<void> show(MediaCapturePermissionGuidePresenter presenter) {
    final existing = _inFlight;
    if (existing != null) return existing;

    late final Future<void> tracked;
    try {
      tracked = presenter().whenComplete(() {
        if (identical(_inFlight, tracked)) {
          _inFlight = null;
        }
      });
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
    _inFlight = tracked;
    return tracked;
  }
}

class MediaCapturePermissionGuideHandler {
  final CanPresentMediaCapturePermissionGuide canPresent;
  final PresentMediaCapturePermissionGuide present;
  final MediaCapturePermissionGuideController _controller;

  MediaCapturePermissionGuideHandler({
    required this.canPresent,
    required this.present,
    MediaCapturePermissionGuideController? controller,
  }) : _controller = controller ?? MediaCapturePermissionGuideController();

  Future<void> handle(Set<WebBridgeMediaCaptureType> types) {
    final isPresentable = canPresent();
    debugPrint(
      '$_mediaPermissionLogTag 引导处理器收到请求 types=$types canPresent=$isPresentable',
    );
    if (types.isEmpty || !isPresentable) return Future<void>.value();
    final requestedTypes = Set<WebBridgeMediaCaptureType>.unmodifiable(types);
    return _controller.show(() async {
      final canStillPresent = canPresent();
      debugPrint(
        '$_mediaPermissionLogTag 准备展示引导 types=$requestedTypes canPresent=$canStillPresent',
      );
      if (!canStillPresent) return;
      await present(requestedTypes);
    });
  }
}

Future<void> showMediaCapturePermissionGuideDialog(
  BuildContext context,
  Set<WebBridgeMediaCaptureType> types, {
  OpenMediaCaptureAppSettings openSettings = openAppSettings,
}) =>
    MediaCapturePermissionGuideDialogPresenter().show(
      context,
      types,
      openSettings: openSettings,
    );

class MediaCapturePermissionGuideDialogPresenter {
  NavigatorState? _navigator;
  Route<void>? _route;

  Future<void> show(
    BuildContext context,
    Set<WebBridgeMediaCaptureType> types, {
    OpenMediaCaptureAppSettings openSettings = openAppSettings,
  }) async {
    if (!context.mounted || types.isEmpty) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      useSafeArea: false,
      builder: (_) => _MediaCapturePermissionGuideDialog(
        types: Set.unmodifiable(types),
        openSettings: openSettings,
      ),
    );
    _navigator = navigator;
    _route = route;
    try {
      await navigator.push(route);
    } finally {
      if (identical(_route, route)) {
        _navigator = null;
        _route = null;
      }
    }
  }

  void dismiss() {
    final navigator = _navigator;
    final route = _route;
    _navigator = null;
    _route = null;
    if (navigator != null && route != null && route.isActive) {
      navigator.removeRoute(route);
    }
  }
}

class _MediaCapturePermissionGuideDialog extends StatelessWidget {
  final Set<WebBridgeMediaCaptureType> types;
  final OpenMediaCaptureAppSettings openSettings;

  const _MediaCapturePermissionGuideDialog({
    required this.types,
    required this.openSettings,
  });

  bool get _needsCamera => types.contains(WebBridgeMediaCaptureType.camera);
  bool get _needsMicrophone =>
      types.contains(WebBridgeMediaCaptureType.microphone);

  String get _title {
    if (_needsCamera && _needsMicrophone) {
      return '摄像头和麦克风权限未开启';
    }
    if (_needsCamera) return '摄像头权限未开启';
    return '麦克风权限未开启';
  }

  String get _message {
    if (_needsCamera && _needsMicrophone) {
      return '使用音视频功能需要摄像头和麦克风权限，请在系统设置中开启后重试。';
    }
    if (_needsCamera) {
      return '使用视频功能需要摄像头权限，请在系统设置中开启后重试。';
    }
    return '使用音频功能需要麦克风权限，请在系统设置中开启后重试。';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        if (bottomPadding > 0)
          Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              width: double.infinity,
              height: bottomPadding,
              color: Colors.white,
            ),
          ),
        SafeArea(
          top: false,
          bottom: true,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        _title,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _message,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: _GuideButton(
                            label: '取消',
                            backgroundColor: const Color(0xFFF5F5F6),
                            foregroundColor: const Color(0xFF51515B),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _GuideButton(
                            label: '去设置',
                            backgroundColor: const Color(0xFF5257EF),
                            foregroundColor: Colors.white,
                            onPressed: () async {
                              Navigator.pop(context);
                              try {
                                await openSettings();
                              } catch (_) {}
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GuideButton extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;

  const _GuideButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: const StadiumBorder(),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
