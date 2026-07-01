import '../model/webview_data.dart';
import 'bridge_context.dart';

/// 能力层基类：一个 Handler 负责一组桥方法。
///
/// 通过 [methods] 声明它能处理哪些 method，[handle] 执行具体逻辑。
/// 宿主可实现自定义 Handler 并注册进 [BridgeDispatcher] 扩展能力。
abstract class BridgeMethodHandler {
  Set<String> get methods;

  Future<void> handle(BridgeContext ctx, WebviewData data);
}
