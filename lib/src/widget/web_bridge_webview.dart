import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../config/web_bridge_config.dart';
import '../core/bridge_context.dart';
import '../core/bridge_dispatcher.dart';
import '../core/bridge_method_handler.dart';
import '../delegate/host_delegate.dart';
import '../delegate/ui_delegate.dart';
import '../handler/default_handlers.dart';
import '../model/webview_data.dart';
import '../util/cookie_helper.dart';
import 'default_load_fail_view.dart';

/// 传输层：承载 WebView、注册 JSBridge channel、注入 Cookie/UA，
/// 并把 H5 消息交给 [BridgeDispatcher] 分发。
///
/// 接入方只需提供 [host]（宿主适配），可选 [config]/[ui]/[extraHandlers]。
class WebBridgeWebView extends StatefulWidget {
  final String url;
  final bool showTitle;
  final WebBridgeHostDelegate host;
  final WebBridgeConfig config;
  final WebBridgeUiDelegate? ui;

  /// 宿主自定义扩展能力，与内置能力一起注册。
  final List<BridgeMethodHandler> extraHandlers;

  const WebBridgeWebView({
    super.key,
    required this.url,
    required this.host,
    this.showTitle = true,
    this.config = const WebBridgeConfig(),
    this.ui,
    this.extraHandlers = const [],
  });

  @override
  State<WebBridgeWebView> createState() => _WebBridgeWebViewState();
}

class _WebBridgeWebViewState extends State<WebBridgeWebView> {
  late final WebViewController _controller;
  late final WebViewCookieManager _cookieManager;
  late final CookieHelper _cookieHelper;
  late final BridgeDispatcher _dispatcher;
  late final WebBridgeUiDelegate _ui;
  late final WebBridgeHostListener _hostListener;

  bool _isInitial = true;
  String _title = '加载中...';
  bool _loadFail = false;
  bool _hasLoadContent = false;

  WebBridgeConfig get _config => widget.config;

  @override
  void initState() {
    super.initState();
    _ui = widget.ui ?? DefaultUiDelegate();
    _cookieManager = WebViewCookieManager();
    _cookieHelper = CookieHelper(widget.host, _config);
    _dispatcher = BridgeDispatcher()
      ..registerAll(buildDefaultHandlers())
      ..registerAll(widget.extraHandlers);

    _hostListener = WebBridgeHostListener(
      onLoggedIn: () {
        _cookieHelper.setCookie(_controller, _cookieManager);
        _controller.runJavaScript('onLoggedIn()');
      },
      onLoggedOut: () {
        _cookieHelper.setCookie(_controller, _cookieManager);
        _controller.runJavaScript('onLoggedOut()');
      },
      onBindStatusChanged: (isBind) {
        _controller.runJavaScript("onBindStatusChanged({'isBind':$isBind})");
      },
      onMembershipChanged: (isChange) {
        _controller
            .runJavaScript("onMembershipChanged({'isChange':$isChange})");
      },
    );
    widget.host.addListener(_hostListener);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(_config.channelName,
          onMessageReceived: (jsMsg) {
        try {
          final Map<String, dynamic> msgMap = jsonDecode(jsMsg.message);
          final data = WebviewData.fromJson(msgMap);
          _dispatcher.dispatch(_buildContext(), data);
        } catch (_) {}
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          _cookieHelper.setCookie(_controller, _cookieManager);
        },
        onPageFinished: (url) async {
          _hasLoadContent = true;
          final title = await _controller.getTitle();
          if (title != null && title.isNotEmpty && mounted) {
            setState(() => _title = title);
          }
          if (Platform.isAndroid) {
            _controller.runJavaScript('''
      document.addEventListener('dragstart', e => {
        if (e.target.tagName.toLowerCase() === 'img') {
          e.preventDefault();
        }
      });
    ''');
          }
        },
        onHttpError: (error) {
          if (!_hasLoadContent && mounted) {
            setState(() {
              _loadFail = true;
              _title = '';
            });
          }
        },
        onWebResourceError: (error) {
          if (!_hasLoadContent && mounted) {
            setState(() {
              _loadFail = true;
              _title = '';
            });
          }
        },
        onNavigationRequest: (request) {
          if (mounted) {
            setState(() => _isInitial = request.url == widget.url);
          }
          return NavigationDecision.navigate;
        },
      ));

    if (_controller.platform is WebKitWebViewController) {
      (_controller.platform as WebKitWebViewController)
          .setAllowsBackForwardNavigationGestures(true);
    }

    _bootstrap();
  }

  BridgeContext _buildContext() => BridgeContext(
        buildContext: context,
        controller: _controller,
        cookieManager: _cookieManager,
        host: widget.host,
        ui: _ui,
        config: _config,
        cookieHelper: _cookieHelper,
      );

  /// 启动流程：先在首帧前把宿主 UA 标识预设好，再加载真实页，
  /// 使真实内容只加载一次（不再 reload，无闪烁、无遮罩依赖）。
  Future<void> _bootstrap() async {
    await _applyUaMarker();
    await _controller.loadRequest(Uri.parse(widget.url));
  }

  /// 首帧前直接读取平台默认 UA（不加载任何页面、不产生历史记录），
  /// 追加宿主标识后 setUserAgent，随后再由 [_bootstrap] 加载真实页——
  /// 无 about:blank 历史项、无二次 reload、无闪烁。
  Future<void> _applyUaMarker() async {
    if (_config.uaMarker.isEmpty) return;
    try {
      final platform = _controller.platform;
      String? ua;
      if (platform is AndroidWebViewController) {
        ua = await platform.getUserAgent();
      } else if (platform is WebKitWebViewController) {
        ua = await platform.getUserAgent();
      }
      if (ua != null && ua.isNotEmpty && !ua.contains(_config.uaMarker)) {
        await _controller.setUserAgent('$ua ${_config.uaMarker}');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          _controller.goBack();
        } else if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    if (!widget.showTitle) {
      return Scaffold(body: _body());
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () async {
            if (await _controller.canGoBack()) {
              _controller.goBack();
            } else if (mounted) {
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(Icons.arrow_back),
        ),
        actions: _appbarActions(),
        title: Text(
          _title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        toolbarHeight: 44,
      ),
      body: _body(),
    );
  }

  List<Widget> _appbarActions() {
    if (!_isInitial) {
      return [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        )
      ];
    }
    return const [];
  }

  Widget _body() {
    if (_loadFail) {
      Future<void> retry() async {
        _controller.loadRequest(Uri.parse(widget.url));
        if (mounted) {
          setState(() {
            _loadFail = false;
            _title = '加载中...';
          });
        }
      }

      return _config.loadFailBuilder?.call(context, retry) ??
          DefaultLoadFailView(retry: retry);
    }
    return WebViewWidget(controller: _controller);
  }

  @override
  void dispose() {
    widget.host.removeListener(_hostListener);
    super.dispose();
  }
}
