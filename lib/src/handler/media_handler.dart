import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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

      // 分享附带文本：title 优先，缺失则退到 desc，再退到 link；都没有则为空。
      // H5 的 title 可能不传，空 title 不应导致分享失败。
      final shareText =
          [title, desc, link].firstWhere((e) => e.isNotEmpty, orElse: () => '');

      if (shareType == 'image' && imgUrl.isNotEmpty) {
        if (ctx.mounted) ctx.ui.showLoading(ctx.buildContext);
        final path = await DownloadUtil.downloadToTemp(imgUrl);
        ctx.ui.dismissLoading();
        if (path != null) {
          // text 传 null（而非空串）：图片本身即可分享，无文本时不附带。
          await Share.shareXFiles([XFile(path)],
              text: shareText.isNotEmpty ? shareText : null);
          return;
        }
      } else if (shareType == 'video' && videoUrl.isNotEmpty) {
        if (ctx.mounted) ctx.ui.showLoading(ctx.buildContext);
        final path = await DownloadUtil.downloadToTemp(videoUrl);
        ctx.ui.dismissLoading();
        if (path != null) {
          await Share.shareXFiles([XFile(path)],
              text: shareText.isNotEmpty ? shareText : null);
          return;
        }
      }
      // 链接分享：拼接 title/desc/link 中的非空项。
      var content = [title, desc, link].where((e) => e.isNotEmpty).join('\n');
      // 图片/视频下载失败会落到这里：无文本时退到 link / img_url / video_url，
      // 保证仍有可分享内容；彻底为空才提示，绝不把空串交给 Share.share
      // （会触发 share_plus 的 text.isNotEmpty 断言而崩溃）。
      if (content.isEmpty) {
        content = [link, imgUrl, videoUrl]
            .firstWhere((e) => e.isNotEmpty, orElse: () => '');
      }
      if (content.isEmpty) {
        if (ctx.mounted) ctx.ui.showToast(ctx.buildContext, '分享内容为空');
        return;
      }
      // 不传 subject：subject 会让系统面板预览只显示标题，且部分第三方会把
      // subject 与正文里的 title 叠加成重复标题。content 已含 标题+描述+链接，
      // 直接作为分享文本，面板与第三方均展示「文本 + 链接」（PRD 要求）。
      await Share.share(content);
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
    // iOS：保存到相册前先受控申请相册权限，被拒时给提示，
    // 避免让 image_gallery_saver_plus 在写入时因缺权限直接失败。
    // 用 Permission.photos（对应宿主 Podfile 已开的 PERMISSION_PHOTOS=1 与
    // Info.plist 的 NSPhotoLibraryUsageDescription）；limited/granted 均可写入。
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      if (!(status.isGranted || status.isLimited)) {
        if (ctx.mounted) ctx.ui.showToast(ctx.buildContext, '未获得相册权限');
        return;
      }
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
