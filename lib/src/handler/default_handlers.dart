import '../core/bridge_method_handler.dart';
import 'account_handler.dart';
import 'download_handler.dart';
import 'event_handler.dart';
import 'media_handler.dart';
import 'member_handler.dart';
import 'ui_handler.dart';

/// 内置能力集合，供 [BridgeDispatcher] 一次性注册。
List<BridgeMethodHandler> buildDefaultHandlers() => [
      AccountHandler(),
      MemberHandler(),
      EventHandler(),
      MediaHandler(),
      DownloadHandler(),
      UiHandler(),
    ];
