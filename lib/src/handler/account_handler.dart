import '../core/bridge_context.dart';
import '../core/bridge_method_handler.dart';
import '../model/webview_data.dart';

/// 账号与通用参数能力：登录/登出/清除、参数获取、登录态查询。
class AccountHandler extends BridgeMethodHandler {
  @override
  Set<String> get methods => {
        'getCommonParams',
        'getExtraParams',
        'getAttribute',
        'getAccountParams',
        'requestLogin',
        'login',
        'requestLogout',
        'requestClearAccount',
        'jumpToUserInfo',
        'isLoggedIn',
      };

  @override
  Future<void> handle(BridgeContext ctx, WebviewData data) async {
    switch (data.method) {
      case 'getCommonParams':
        ctx.callbackString(data.callback, await ctx.host.getCommonParams());
        break;
      case 'getExtraParams':
        ctx.callbackString(data.callback, await ctx.host.getExtraParams());
        break;
      case 'getAttribute':
        ctx.callbackString(data.callback, await ctx.host.getAttribute());
        break;
      case 'getAccountParams':
        ctx.callbackString(data.callback, await ctx.host.getAccountParams());
        break;
      case 'requestLogin':
      case 'login':
        await ctx.host.requestLogin();
        await ctx.setCookie();
        break;
      case 'requestLogout':
        await ctx.host.requestLogout();
        await ctx.setCookie();
        break;
      case 'requestClearAccount':
        await ctx.host.requestClearAccount();
        await ctx.setCookie();
        break;
      case 'jumpToUserInfo':
        await ctx.host.jumpToUserInfo();
        break;
      case 'isLoggedIn':
        ctx.callbackRaw(data.callback, await ctx.host.isLoggedIn());
        break;
    }
  }
}
