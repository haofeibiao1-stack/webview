import '../core/bridge_context.dart';
import '../core/bridge_method_handler.dart';
import '../model/webview_data.dart';

/// 页面控制与轻交互能力：Toast、Cookie 注入、关闭页面。
class UiHandler extends BridgeMethodHandler {
  @override
  Set<String> get methods => {'showToast', 'setCookie', 'closePage'};

  @override
  Future<void> handle(BridgeContext ctx, WebviewData data) async {
    switch (data.method) {
      case 'showToast':
        if (ctx.mounted) {
          ctx.ui.showToast(
              ctx.buildContext, data.params['message']?.toString() ?? '');
        }
        break;
      case 'setCookie':
        await ctx.setCookie(path: data.params['host']?.toString());
        break;
      case 'closePage':
        ctx.host.closePage();
        break;
    }
  }
}
