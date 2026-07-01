import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 分享/保存相册共用的下载与文件名工具。
class DownloadUtil {
  /// 下载远程文件到临时目录，返回本地路径，失败返回 null。
  static Future<String?> downloadToTemp(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/${fileNameFromUrl(url, isVideoUrl(url))}';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      return filePath;
    } catch (_) {
      return null;
    }
  }

  static bool isVideoUrl(String url) {
    final path = url.split('?').first.toLowerCase();
    return path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.m4v') ||
        path.endsWith('.3gp') ||
        path.endsWith('.avi') ||
        path.endsWith('.mkv');
  }

  static String fileNameFromUrl(String url, bool isVideo) {
    final path = url.split('?').first;
    final name = path.contains('/') ? path.split('/').last : path;
    if (name.isNotEmpty && name.contains('.')) {
      return name;
    }
    final ext = isVideo ? 'mp4' : 'jpg';
    return 'webview_bridge_${DateTime.now().millisecondsSinceEpoch}.$ext';
  }
}
