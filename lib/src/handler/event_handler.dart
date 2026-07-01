import 'dart:convert';

import '../core/bridge_context.dart';
import '../core/bridge_method_handler.dart';
import '../model/webview_data.dart';

/// 埋点与功能跳转能力：onEvent / manualActive / funcJump。
class EventHandler extends BridgeMethodHandler {
  @override
  Set<String> get methods => {'onEvent', 'manualActive', 'funcJump'};

  @override
  Future<void> handle(BridgeContext ctx, WebviewData data) async {
    final params = data.params;
    switch (data.method) {
      case 'onEvent':
        await ctx.host
            .onEvent(params['eventId'], map: _convertMap(params['extra']));
        break;
      case 'manualActive':
        await ctx.host.manualActive(params['manualType']);
        break;
      case 'funcJump':
        ctx.host.funcJump(
          params['jumpType'] ?? '',
          params['path'] ?? '',
          jsonEncode(params['extra'] ?? {}),
          params['from'] ?? '',
          params['funcId'] ?? '',
        );
        await ctx.host.manualActive(params['manualType']);
        break;
    }
  }

  Map<String, String> _convertMap(Map<dynamic, dynamic>? map) {
    final result = <String, String>{};
    if (map == null) return result;
    map.forEach((key, value) {
      if (key != null && value != null) {
        result[key.toString()] = value.toString();
      }
    });
    return result;
  }
}
