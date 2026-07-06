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
        ctx.emitResult(data.callback, data: await ctx.host.getCommonParams());
        break;
      case 'getExtraParams':
        ctx.emitResult(data.callback, data: await ctx.host.getExtraParams());
        break;
      case 'getAttribute':
        ctx.emitResult(data.callback, data: await ctx.host.getAttribute());
        break;
      case 'getAccountParams':
        ctx.emitResult(data.callback, data: await ctx.host.getAccountParams());
        break;
      case 'requestLogin':
        // guardRequestLogin 时复刻文库存量逻辑：仅在未登录时触发登录 + 种 Cookie。
        if (!(ctx.config.guardRequestLogin && await ctx.host.isLoggedIn())) {
          await ctx.host.requestLogin();
          await ctx.setCookie();
        }
        break;
      case 'login':
        // 运营能力登录按钮：已登录跳个人信息页，未登录才拉起登录并种 Cookie。
        // 不能与 requestLogin 合并——合并后已登录时什么都不做，
        // 会出现「登录完成再点 login 无反应」。
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
        ctx.emitResult(data.callback, data: await ctx.host.isLoggedIn());
        break;
    }
  }
}
