/// 宿主提供的账号态，用于向 WebView 注入登录 Cookie。
class WebBridgeAccount {
  /// 360 账号 Q 值。
  final String q;

  /// 360 账号 T 值。
  final String t;

  const WebBridgeAccount({this.q = '', this.t = ''});
}
