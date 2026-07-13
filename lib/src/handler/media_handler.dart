import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../core/bridge_context.dart';
import '../core/bridge_method_handler.dart';
import '../model/webview_data.dart';
import '../util/download_util.dart';

/// 媒体处理调试日志统一前缀，便于 logcat/Console 过滤定位分享/保存问题。
const String _kShareLogTag = '【WebBridge-Media】';


/// 自包含能力：系统分享（链接/图片/视频）与保存到相册。
///
/// 图片/视频等耗时操作会先下载，期间通过 UiDelegate 展示 Loading。
class MediaHandler extends BridgeMethodHandler {
  @override
  Set<String> get methods => {'share', 'savePhotoAndVideo'};

  @override
  Future<void> handle(BridgeContext ctx, WebviewData data) async {
    print('$_kShareLogTag handle 收到H5调用 method=${data.method} '
        'params=${data.params}');
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
    print('$_kShareLogTag [savePhotoAndVideo] H5请求保存 url=$url');
    if (url.isEmpty) {
      print('$_kShareLogTag [savePhotoAndVideo] url为空，终止保存');
      if (ctx.mounted) ctx.ui.showToast(ctx.buildContext, '保存失败');
      return;
    }
    // iOS：保存到相册前先受控申请相册权限，被拒时给提示，
    // 避免让 image_gallery_saver_plus 在写入时因缺权限直接失败。
    // 用 Permission.photos（对应宿主 Podfile 已开的 PERMISSION_PHOTOS=1 与
    // Info.plist 的 NSPhotoLibraryUsageDescription）；limited/granted 均可写入。
    if (Platform.isIOS) {
      // 先查当前状态，区分「尚未询问」与「已被拒绝」两种情况：
      // - granted/limited：已授权，直接保存；
      // - permanentlyDenied：此前已拒绝，iOS 不会再弹原生授权框，此时（且仅此时）
      //   弹自定义引导弹窗，点「去设置」跳系统设置手动开启；
      // - denied（iOS 的未决定态）：首次询问，调 request() 弹系统原生框，用户在
      //   原生框内的选择不叠加自定义引导（未选择/授权都不弹引导）。
      var status = await Permission.photos.status;
      print('$_kShareLogTag [savePhotoAndVideo] iOS相册当前权限状态=$status');
      if (status.isPermanentlyDenied) {
        print('$_kShareLogTag [savePhotoAndVideo] 相册权限此前已拒绝，弹引导弹窗 status=$status');
        if (ctx.mounted) {
          await _showPhotoPermissionGuideDialog(ctx.buildContext);
        }
        return;
      }
      if (!(status.isGranted || status.isLimited)) {
        // 未决定态：弹系统原生授权框；结果不再叠加自定义引导，仅在被拒时给 toast 反馈。
        status = await Permission.photos.request();
        print('$_kShareLogTag [savePhotoAndVideo] iOS相册请求后权限状态=$status');
        if (!(status.isGranted || status.isLimited)) {
          print('$_kShareLogTag [savePhotoAndVideo] 原生框未授权，终止（不弹引导）status=$status');
          if (ctx.mounted) ctx.ui.showToast(ctx.buildContext, '未获得相册权限');
          return;
        }
      }
    }
    if (ctx.mounted) ctx.ui.showLoading(ctx.buildContext);
    try {
      final isVideo = DownloadUtil.isVideoUrl(url);
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        print('$_kShareLogTag [savePhotoAndVideo] 下载失败 statusCode=${response.statusCode}');
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
        print('$_kShareLogTag [savePhotoAndVideo] 视频写入临时文件=$filePath');
        result = await ImageGallerySaverPlus.saveFile(filePath,
            isReturnPathOfIOS: true);
      } else {
        final fileName = DownloadUtil.fileNameFromUrl(url, false);
        print('$_kShareLogTag [savePhotoAndVideo] 保存图片 name=$fileName');
        result = await ImageGallerySaverPlus.saveImage(response.bodyBytes,
            name: fileName);
      }
      final success = result is Map && result['isSuccess'] == true;
      print('$_kShareLogTag [savePhotoAndVideo] 保存结果 result=$result success=$success');
      ctx.ui.dismissLoading();
      if (ctx.mounted) {
        ctx.ui.showToast(ctx.buildContext, success ? '已保存到相册' : '保存失败');
      }
    } catch (e, s) {
      print('$_kShareLogTag [savePhotoAndVideo] 保存异常 error=$e\n$s');
      ctx.ui.dismissLoading();
      if (ctx.mounted) ctx.ui.showToast(ctx.buildContext, '保存失败');
    }
  }

  /// 相册权限被拒后的引导弹窗：底部白色卡片，「去设置」跳系统设置手动开启。
  Future<void> _showPhotoPermissionGuideDialog(BuildContext context) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (_) => const _PhotoPermissionGuideDialog(),
    );
  }
}

/// 相册权限引导弹窗，样式对齐宿主 PermissionDialogWidget（底部圆角卡片）。
class _PhotoPermissionGuideDialog extends StatelessWidget {
  const _PhotoPermissionGuideDialog();

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Stack(children: [
      if (bottomPadding > 0)
        Align(
          alignment: Alignment.bottomLeft,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                  child: Container(height: bottomPadding, color: Colors.white)),
            ],
          ),
        ),
      SafeArea(
        top: false,
        bottom: true,
        child: Stack(children: [
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                  left: 24, right: 24, top: 32, bottom: 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text(
                      '相册权限未开启',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '保存图片和视频需要访问相册权限，请在系统设置中开启「照片」权限后重试。',
                    style: TextStyle(fontSize: 14, color: Colors.black),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Container(
                              alignment: Alignment.center,
                              height: 48,
                              decoration: const BoxDecoration(
                                  color: Color(0xFFF5F5F6),
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(100))),
                              width: double.infinity,
                              child: const Text(
                                '取消',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF51515B)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              openAppSettings();
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Container(
                              alignment: Alignment.center,
                              height: 48,
                              decoration: const BoxDecoration(
                                  color: Color(0xFF5257EF),
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(100))),
                              width: double.infinity,
                              child: const Text(
                                '去设置',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}
