import 'package:permission_handler/permission_handler.dart';

import 'media_capture_permission.dart';

typedef PermissionBatchRequester = Future<Map<Permission, PermissionStatus>>
    Function(List<Permission> permissions);
typedef PermissionStatusGetter = Future<PermissionStatus> Function(
  Permission permission,
);

enum MediaCapturePermissionDecision {
  granted,
  denied,
  permanentlyDenied,
}

class MediaCapturePermissionResult {
  final MediaCapturePermissionDecision decision;
  final Set<WebBridgeMediaCaptureType> permanentlyDeniedTypes;

  /// 仅当权限在本次 H5 请求开始前就已永久拒绝时展示设置引导。
  final bool shouldShowSettingsGuide;
  final bool Function()? _currentPageValidator;

  const MediaCapturePermissionResult.granted()
      : decision = MediaCapturePermissionDecision.granted,
        permanentlyDeniedTypes = const {},
        shouldShowSettingsGuide = false,
        _currentPageValidator = null;

  const MediaCapturePermissionResult.denied()
      : decision = MediaCapturePermissionDecision.denied,
        permanentlyDeniedTypes = const {},
        shouldShowSettingsGuide = false,
        _currentPageValidator = null;

  MediaCapturePermissionResult.permanentlyDenied(
    Set<WebBridgeMediaCaptureType> types, {
    this.shouldShowSettingsGuide = true,
  })  : decision = MediaCapturePermissionDecision.permanentlyDenied,
        permanentlyDeniedTypes = Set.unmodifiable(types),
        _currentPageValidator = null;

  MediaCapturePermissionResult._(
    this.decision,
    this.permanentlyDeniedTypes,
    this.shouldShowSettingsGuide,
    this._currentPageValidator,
  );

  bool get isGranted => decision == MediaCapturePermissionDecision.granted;

  bool get isCurrentPage {
    try {
      return _currentPageValidator?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  MediaCapturePermissionResult withCurrentPageValidator(
    bool Function() validator,
  ) =>
      MediaCapturePermissionResult._(
        decision,
        permanentlyDeniedTypes,
        shouldShowSettingsGuide,
        validator,
      );

  MediaCapturePermissionResult withSettingsGuideVisibility(bool shouldShow) =>
      MediaCapturePermissionResult._(
        decision,
        permanentlyDeniedTypes,
        shouldShow,
        _currentPageValidator,
      );
}

/// 使用 permission_handler 申请 H5 媒体采集所需的系统权限。
class PermissionHandlerMediaCaptureRequester {
  final PermissionBatchRequester _requestPermissions;
  final PermissionStatusGetter _getPermissionStatus;

  PermissionHandlerMediaCaptureRequester({
    PermissionBatchRequester? requestPermissions,
    PermissionStatusGetter? getPermissionStatus,
  })  : _requestPermissions = requestPermissions ?? _request,
        _getPermissionStatus = getPermissionStatus ?? _status;

  static Future<Map<Permission, PermissionStatus>> _request(
    List<Permission> permissions,
  ) =>
      permissions.request();

  static Future<PermissionStatus> _status(Permission permission) =>
      permission.status;

  Future<MediaCapturePermissionResult> request(
    Set<WebBridgeMediaCaptureType> types,
  ) async {
    final permissionTypes = <Permission, WebBridgeMediaCaptureType>{
      if (types.contains(WebBridgeMediaCaptureType.camera))
        Permission.camera: WebBridgeMediaCaptureType.camera,
      if (types.contains(WebBridgeMediaCaptureType.microphone))
        Permission.microphone: WebBridgeMediaCaptureType.microphone,
    };
    if (permissionTypes.isEmpty) {
      return const MediaCapturePermissionResult.denied();
    }

    final permanentlyDeniedTypes = <WebBridgeMediaCaptureType>{};
    final permissionsToRequest = <Permission, WebBridgeMediaCaptureType>{};
    for (final entry in permissionTypes.entries) {
      final status = await _getPermissionStatus(entry.key);
      if (status.isPermanentlyDenied) {
        permanentlyDeniedTypes.add(entry.value);
      } else if (!status.isGranted) {
        permissionsToRequest[entry.key] = entry.value;
      }
    }
    if (permanentlyDeniedTypes.isNotEmpty) {
      return MediaCapturePermissionResult.permanentlyDenied(
        permanentlyDeniedTypes,
      );
    }
    if (permissionsToRequest.isEmpty) {
      return const MediaCapturePermissionResult.granted();
    }

    final statuses =
        await _requestPermissions(permissionsToRequest.keys.toList());
    permanentlyDeniedTypes.addAll(
      permissionsToRequest.entries
          .where(
            (entry) => statuses[entry.key]?.isPermanentlyDenied ?? false,
          )
          .map((entry) => entry.value),
    );
    if (permanentlyDeniedTypes.isNotEmpty) {
      return MediaCapturePermissionResult.permanentlyDenied(
        permanentlyDeniedTypes,
        shouldShowSettingsGuide: false,
      );
    }
    if (permissionsToRequest.keys.every(
      (permission) => statuses[permission]?.isGranted ?? false,
    )) {
      return const MediaCapturePermissionResult.granted();
    }
    return const MediaCapturePermissionResult.denied();
  }
}
