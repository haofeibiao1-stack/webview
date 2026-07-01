import '../core/bridge_context.dart';
import '../core/bridge_method_handler.dart';
import '../model/webview_data.dart';

/// 会员与游客能力：会员态查询、会员页、游客绑定、会员刷新。
class MemberHandler extends BridgeMethodHandler {
  @override
  Set<String> get methods => {
        'isMemberShip',
        'getMemberInfo',
        'startMemberPage',
        'bindTourist',
        'isTouristMembership',
        'isTouristModeEnable',
        'refreshMember',
      };

  @override
  Future<void> handle(BridgeContext ctx, WebviewData data) async {
    final params = data.params;
    switch (data.method) {
      case 'isMemberShip':
        ctx.callbackRaw(data.callback, await ctx.host.isMemberShip());
        break;
      case 'getMemberInfo':
        ctx.callbackString(data.callback, await ctx.host.getMemberInfo());
        break;
      case 'startMemberPage':
        await ctx.host.startMemberPage(
          isFullScreen: params['isFullScreen'] ?? true,
          memberStatus: params['memberStatus'] ?? 0,
          from: params['from'] ?? '',
          module: params['module'] ?? '',
          standType: params['standType'] ?? '',
          extra: params['extra'],
        );
        break;
      case 'bindTourist':
        await ctx.host.bindTourist(params['extra']);
        break;
      case 'isTouristMembership':
        ctx.callbackRaw(data.callback, await ctx.host.isTouristMembership());
        break;
      case 'isTouristModeEnable':
        ctx.callbackRaw(data.callback, await ctx.host.isTouristModeEnable());
        break;
      case 'refreshMember':
        await ctx.host.refreshMember();
        break;
    }
  }
}
