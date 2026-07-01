/// H5 通过 JSBridge 下发的一次调用数据。
///
/// H5 侧调用约定:
/// `channel.postMessage(JSON.stringify({ method, params, callback }))`
class WebviewData {
  /// 桥方法名，对应各 Handler 声明的 methods。
  final String method;

  /// 方法参数，H5 传入的任意 JSON 对象。
  final Map<dynamic, dynamic> params;

  /// H5 侧回调函数名，能力执行完通过 runJavaScript 回调。
  final String callback;

  const WebviewData({
    this.method = '',
    this.params = const {},
    this.callback = '',
  });

  factory WebviewData.fromJson(Map<String, dynamic> json) {
    final rawParams = json['params'];
    return WebviewData(
      method: json['method']?.toString() ?? '',
      params: rawParams is Map ? rawParams : const {},
      callback: json['callback']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'method': method,
        'params': params,
        'callback': callback,
      };
}
