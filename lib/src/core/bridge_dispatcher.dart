import '../model/webview_data.dart';
import 'bridge_context.dart';
import 'bridge_method_handler.dart';

/// 分发层：以 method 名为 key 的 Handler 注册表，替代原先的巨型 switch。
///
/// 新增能力只需注册新 Handler，无需改动分发逻辑（开闭原则）。
class BridgeDispatcher {
  final Map<String, BridgeMethodHandler> _handlers = {};

  void register(BridgeMethodHandler handler) {
    for (final m in handler.methods) {
      _handlers[m] = handler;
    }
  }

  void registerAll(Iterable<BridgeMethodHandler> handlers) {
    for (final h in handlers) {
      register(h);
    }
  }

  bool canHandle(String method) => _handlers.containsKey(method);

  Future<void> dispatch(BridgeContext ctx, WebviewData data) async {
    final handler = _handlers[data.method];
    if (handler == null) return;
    try {
      await handler.handle(ctx, data);
    } catch (_) {}
  }
}
