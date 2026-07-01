import 'package:flutter/foundation.dart';

import '../model/web_bridge_account.dart';

/// 宿主态变化监听器，插件内部用它把 native 事件回调给 H5。
class WebBridgeHostListener {
  final VoidCallback? onLoggedIn;
  final VoidCallback? onLoggedOut;
  final ValueChanged<bool>? onBindStatusChanged;
  final ValueChanged<bool>? onMembershipChanged;

  const WebBridgeHostListener({
    this.onLoggedIn,
    this.onLoggedOut,
    this.onBindStatusChanged,
    this.onMembershipChanged,
  });
}

/// 宿主适配层：把所有依赖具体 App 的能力（账号、会员、埋点、路由、
/// 文件保存回调等）抽象成接口，由各接入方提供实现。
///
/// 自包含能力（分享、保存相册、下载、Toast、Cookie 注入）不在此接口内，
/// 由插件直接实现。
abstract class WebBridgeHostDelegate {
  /// 供 Cookie 注入使用的账号态。
  Future<WebBridgeAccount?> getAccount();

  Future<String> getCommonParams();

  Future<String> getExtraParams();

  Future<String> getAttribute();

  Future<String> getAccountParams();

  Future<void> requestLogin();

  Future<void> requestLogout();

  Future<void> requestClearAccount();

  Future<void> jumpToUserInfo();

  Future<bool> isLoggedIn();

  Future<bool> isMemberShip();

  Future<String> getMemberInfo();

  Future<void> startMemberPage({
    bool isFullScreen,
    int memberStatus,
    String from,
    String module,
    String standType,
    dynamic extra,
  });

  Future<void> bindTourist(dynamic extra);

  Future<bool> isTouristMembership();

  Future<bool> isTouristModeEnable();

  Future<void> onEvent(String eventId, {Map<String, String> map});

  Future<void> manualActive(dynamic manualType);

  /// 功能跳转（对应宿主的 globalJumpFunc）。
  void funcJump(
    String jumpType,
    String path,
    String extra,
    String from,
    String funcId,
  );

  /// 刷新会员态（对应宿主的 globalRefreshMember）。
  Future<void> refreshMember();

  /// 文件下载完成后回调宿主记录路径（对应 globalPostSavePath）。
  void onFileSaved(String path);

  /// 打开「最近保存文件」页（对应 AiWorkLib.openFilePage）。
  void openFilePage();

  /// 关闭当前 WebView 页（对应 globalRouter?.pop()）。
  void closePage();

  /// 注册宿主态监听（登录/会员/绑定变化）。
  void addListener(WebBridgeHostListener listener);

  void removeListener(WebBridgeHostListener listener);
}
