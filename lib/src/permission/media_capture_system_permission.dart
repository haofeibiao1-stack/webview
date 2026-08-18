import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'media_capture_permission.dart';

const _mediaPermissionLogTag = '【WebBridge-MediaPermission】';

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
    debugPrint('$_mediaPermissionLogTag 系统权限申请开始 types=$types');
    final permissionTypes = <Permission, WebBridgeMediaCaptureType>{
      if (types.contains(WebBridgeMediaCaptureType.camera))
        Permission.camera: WebBridgeMediaCaptureType.camera,
      if (types.contains(WebBridgeMediaCaptureType.microphone))
        Permission.microphone: WebBridgeMediaCaptureType.microphone,
    };
    if (permissionTypes.isEmpty) {
      return _finish(
        types,
        const MediaCapturePermissionResult.denied(),
        const {},
        const {},
      );
    }

    final permanentlyDeniedTypes = <WebBridgeMediaCaptureType>{};
    final permissionsToRequest = <Permission, WebBridgeMediaCaptureType>{};
    final statusBeforeRequest = <Permission, PermissionStatus>{};
    for (final entry in permissionTypes.entries) {
      final status = await _getPermissionStatus(entry.key);
      statusBeforeRequest[entry.key] = status;
      debugPrint(
        '$_mediaPermissionLogTag 申请前状态 permission=${entry.key} status=$status',
      );
      if (status.isPermanentlyDenied) {
        permanentlyDeniedTypes.add(entry.value);
      } else if (!status.isGranted) {
        permissionsToRequest[entry.key] = entry.value;
      }
    }
    if (permanentlyDeniedTypes.isNotEmpty) {
      debugPrint(
        '$_mediaPermissionLogTag 申请前已永久拒绝 types=$permanentlyDeniedTypes，允许展示设置引导',
      );
      return _finish(
        types,
        MediaCapturePermissionResult.permanentlyDenied(
          permanentlyDeniedTypes,
        ),
        statusBeforeRequest,
        const {},
      );
    }
    if (permissionsToRequest.isEmpty) {
      return _finish(
        types,
        const MediaCapturePermissionResult.granted(),
        statusBeforeRequest,
        const {},
      );
    }

    final statuses =
        await _requestPermissions(permissionsToRequest.keys.toList());
    debugPrint('$_mediaPermissionLogTag 系统申请结果 statuses=$statuses');
    permanentlyDeniedTypes.addAll(
      permissionsToRequest.entries
          .where(
            (entry) => statuses[entry.key]?.isPermanentlyDenied ?? false,
          )
          .map((entry) => entry.value),
    );
    if (permanentlyDeniedTypes.isNotEmpty) {
      debugPrint(
        '$_mediaPermissionLogTag 本次申请后变为永久拒绝 types=$permanentlyDeniedTypes，不立即展示设置引导',
      );
      return _finish(
        types,
        MediaCapturePermissionResult.permanentlyDenied(
          permanentlyDeniedTypes,
          shouldShowSettingsGuide: false,
        ),
        statusBeforeRequest,
        statuses,
      );
    }
    if (permissionsToRequest.keys.every(
      (permission) => statuses[permission]?.isGranted ?? false,
    )) {
      return _finish(
        types,
        const MediaCapturePermissionResult.granted(),
        statusBeforeRequest,
        statuses,
      );
    }
    return _finish(
      types,
      const MediaCapturePermissionResult.denied(),
      statusBeforeRequest,
      statuses,
    );
  }

  /// 只读取并记录当前系统权限，用于定位 H5 没有触发原生回调的场景。
  Future<void> logCurrentStatusSnapshot({required String reason}) async {
    final statuses = <Permission, PermissionStatus>{};
    for (final permission in const [Permission.camera, Permission.microphone]) {
      statuses[permission] = await _getPermissionStatus(permission);
    }
    debugPrint(
      '$_mediaPermissionLogTag 系统权限状态快照 reason=$reason statuses=$statuses',
    );
  }

  MediaCapturePermissionResult _finish(
    Set<WebBridgeMediaCaptureType> types,
    MediaCapturePermissionResult result,
    Map<Permission, PermissionStatus> before,
    Map<Permission, PermissionStatus> after,
  ) {
    debugPrint(
      '$_mediaPermissionLogTag 系统权限流程结束 '
      'types=$types before=$before after=$after '
      'decision=${result.decision} '
      'permanent=${result.permanentlyDeniedTypes} '
      'showGuide=${result.shouldShowSettingsGuide}',
    );
    return result;
  }
}
