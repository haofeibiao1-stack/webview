import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/bridge_context.dart';
import '../core/bridge_method_handler.dart';
import '../model/webview_data.dart';

/// 文件下载能力：下载到公共目录，回调宿主记录路径并回调 H5 onDownload。
class DownloadHandler extends BridgeMethodHandler {
  @override
  Set<String> get methods => {'downloadFile'};

  @override
  Future<void> handle(BridgeContext ctx, WebviewData data) async {
    final url = data.params['url']?.toString() ?? '';
    final name = data.params['fileName']?.toString() ?? '';
    await _downloadFile(ctx, url, name);
  }

  Future<void> _downloadFile(
      BridgeContext ctx, String url, String name) async {
    if (url.isEmpty || name.isEmpty) {
      _fail(ctx);
      return;
    }
    Directory? directory;
    if (Platform.isIOS || Platform.operatingSystem == 'ohos') {
      directory = await getApplicationDocumentsDirectory();
    } else {
      directory = await getDownloadsDirectory();
    }
    if (directory == null) {
      _fail(ctx);
      return;
    }
    if (ctx.mounted) ctx.ui.showLoading(ctx.buildContext);
    final filePath = '${directory.path}/$name';
    final file = File(filePath);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        ctx.host.onFileSaved(filePath);
        ctx.ui.dismissLoading();
        if (ctx.mounted) {
          ctx.ui.showToast(ctx.buildContext, '已保存至【最近保存文件】',
              action: '去查看', onClick: () {
            ctx.host.closePage();
            ctx.host.openFilePage();
          });
          ctx.runJs("onDownload({'result':true})");
        }
      } else {
        if (file.existsSync()) file.deleteSync();
        _fail(ctx);
      }
    } catch (_) {
      if (file.existsSync()) file.deleteSync();
      _fail(ctx);
    }
  }

  void _fail(BridgeContext ctx) {
    ctx.ui.dismissLoading();
    if (ctx.mounted) ctx.ui.showToast(ctx.buildContext, '文件下载失败！');
    ctx.runJs("onDownload({'result':false})");
  }
}
