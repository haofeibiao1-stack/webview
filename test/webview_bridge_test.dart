import 'package:flutter_test/flutter_test.dart';
import 'package:webview_bridge/webview_bridge.dart';

void main() {
  test('WebviewData.fromJson 容错解析', () {
    final data = WebviewData.fromJson({
      'method': 'share',
      'params': {'url': 'https://a.com/x.png'},
      'callback': 'cb',
    });
    expect(data.method, 'share');
    expect(data.params['url'], 'https://a.com/x.png');
    expect(data.callback, 'cb');
  });

  test('WebviewData.fromJson 缺字段不抛异常', () {
    final data = WebviewData.fromJson({'method': 'login'});
    expect(data.method, 'login');
    expect(data.params, isEmpty);
    expect(data.callback, '');
  });
}
