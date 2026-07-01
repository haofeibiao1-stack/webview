import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/bridge_context.dart';
import '../core/bridge_method_handler.dart';
import '../model/webview_data.dart';
import '../util/download_util.dart';

/// 自包含能力：系统分享（链接/图片/视频）与保存到相册。
///
/// 图片/视频等耗时操作会先下载，期间通过 UiDelegate 展示 Loading。
class MediaHandler extends BridgeMethodHandler {
  @override
  Set<String> get methods => {'share', 'savePhotoAndVideo'};

  @override
  Future<void> handle(BridgeContext ctx, WebviewData data) async {
    switch (data.method) {
      case 'share':
        await _shareToSystem(ctx, data.params);
        break;
      case 'savePhotoAndVideo':
        await _savePhotoAndVideo(ctx, data.params['url']?.toString() ?? '');
        break;
    }
  }

  /// 系统分享：按 share_type 分享链接 / 图片 / 视频。
  /// params: { share_type: "link|image|video",
  ///   weixin: { title, desc, link, img_url, video_url } }
  Future<void> _shareToSystem(
      BridgeContext ctx, Map<dynamic, dynamic> params) async {
    try {
      final shareType = params['share_type']?.toString() ?? 'link';
      final weixin =
          (params['weixin'] is Map) ? params['weixin'] as Map : params;
      final title = weixin['title']?.toString() ?? '';
      final desc = weixin['desc']?.toString() ?? '';
      final link = weixin['link']?.toString() ?? '';
      final imgUrl = weixin['img_url']?.toString() ?? '';
      final videoUrl = weixin['video_url']?.toString() ?? '';

      if (shareType == 'image' && imgUrl.isNotEmpty) {
        if (ctx.mounted) ctx.ui.showLoading(ctx.buildContext);
        final path = await DownloadUtil.downloadToTemp(imgUrl);
        ctx.ui.dismissLoading();
        if (path != null) {
          await Share.shareXFiles([XFile(path)],
              text: title.isNotEmpty ? title : desc);
          return;
        }
      } else if (shareType == 'video' && videoUrl.isNotEmpty) {
        if (ctx.mounted) ctx.ui.showLoading(ctx.buildContext);
        final path = await DownloadUtil.downloadToTemp(videoUrl);
        ctx.ui.dismissLoading();
        if (path != null) {
          await Share.shareXFiles([XFile(path)],
              text: title.isNotEmpty ? title : desc);
          return;
        }
      }
      var content = [title, desc, link].where((e) => e.isNotEmpty).join('\n');
      if (content.isEmpty) content = link;
      await Share.share(content, subject: title.isNotEmpty ? title : null);
    } catch (_) {
      ctx.ui.dismissLoading();
      if (ctx.mounted) ctx.ui.showToast(ctx.buildContext, '分享失败');
    }
  }

  /// 保存图片 / 视频到系统相册。
  Future<void> _savePhotoAndVideo(BridgeContext ctx, String url) async {
    if (url.isEmpty) {
      if (ctx.mounted) ctx.ui.showToast(ctx.buildContext, '保存失败');
      return;
    }
    if (ctx.mounted) ctx.ui.showLoading(ctx.buildContext);
    try {
      final isVideo = DownloadUtil.isVideoUrl(url);
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        ctx.ui.dismissLoading();
        if (ctx.mounted) ctx.ui.showToast(ctx.buildContext, '保存失败');
        return;
      }
      dynamic result;
      if (isVideo) {
        final dir = await getTemporaryDirectory();
        final filePath =
            '${dir.path}/${DownloadUtil.fileNameFromUrl(url, true)}';
        await File(filePath).writeAsBytes(response.bodyBytes);
        result = await ImageGallerySaverPlus.saveFile(filePath,
            isReturnPathOfIOS: true);
      } else {
        result = await ImageGallerySaverPlus.saveImage(response.bodyBytes,
            name: DownloadUtil.fileNameFromUrl(url, false));
      }
      final success = result is Map && result['isSuccess'] == true;
      ctx.ui.dismissLoading();
      if (ctx.mounted) {
        ctx.ui.showToast(ctx.buildContext, success ? '已保存到相册' : '保存失败');
      }
    } catch (_) {
      ctx.ui.dismissLoading();
      if (ctx.mounted) ctx.ui.showToast(ctx.buildContext, '保存失败');
    }
  }
}
