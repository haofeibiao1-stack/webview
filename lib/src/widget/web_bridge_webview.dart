import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  /// 内嵌模式：为 true 时不自建 Scaffold / 标题栏 / 返回拦截，
  /// 供宿主页（自带 AppBar、自管返回）直接嵌入 WebView 本体。
  final bool embedded;

  /// 加载遮罩：为 true 时在页面加载完成前覆盖一层占位（默认转圈），
  /// 加载完成（onPageFinished 或进度 100）后移除。
  final bool showLoading;

  /// WebViewController 创建后回调一次，供宿主页持有并直接执行 JS
  /// （替代文库旧 `setWebViewController`）。
  final ValueChanged<WebViewController>? onControllerCreated;

  /// 页面加载进度回调（0-100）。
  final ValueChanged<int>? onProgress;

  /// 页面开始加载回调（对应文库旧 `Webview` 的 onPageStarted，用于宿主页
  /// 自绘 Loading / 刷新标题）。
  final ValueChanged<String>? onPageStarted;

  /// 页面加载完成回调（对应文库旧 `Webview` 的 onPageFinished）。
  final ValueChanged<String>? onPageFinished;

  /// 未被任何 Handler 处理的 H5 消息兜底，交由宿主页自行处理
  /// （对应文库旧 `Webview.onMessage`）。
  final ValueChanged<WebviewData>? onMessage;

  const WebBridgeWebView({
    super.key,
    required this.url,
    required this.host,
    this.showTitle = true,
    this.config = const WebBridgeConfig(),
    this.ui,
    this.extraHandlers = const [],
    this.embedded = false,
    this.showLoading = false,
    this.onControllerCreated,
    this.onProgress,
    this.onPageStarted,
    this.onPageFinished,
    this.onMessage,
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
  int _progress = 0;

  bool get _pageReady => _hasLoadContent || _progress >= 100;

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

    final PlatformWebViewControllerCreationParams creationParams;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      creationParams = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: _config.enableInlineMediaPlayback,
        mediaTypesRequiringUserAction: _config.mediaAutoPlay
            ? const <PlaybackMediaTypes>{}
            : const {PlaybackMediaTypes.audio, PlaybackMediaTypes.video},
      );
    } else {
      creationParams = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(creationParams)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(_config.channelName,
          onMessageReceived: (jsMsg) async {
        try {
          final Map<String, dynamic> msgMap = jsonDecode(jsMsg.message);
          final data = WebviewData.fromJson(msgMap);
          if (_dispatcher.canHandle(data.method)) {
            final ctx = _buildContext();
            await _dispatcher.dispatch(ctx, data);
            // 复刻文库存量「无论何种方法都回一次成功」：已回过数据的不再重复。
            if (_config.autoSuccessCallback &&
                data.callback.isNotEmpty &&
                !ctx.didCallback) {
              ctx.emitResult(data.callback);
            }
          } else {
            widget.onMessage?.call(data);
            if (_config.autoSuccessCallback && data.callback.isNotEmpty) {
              _buildContext().emitResult(data.callback);
            }
          }
        } catch (_) {}
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          if (_config.seedCookieOnPageStarted) {
            _cookieHelper.setCookie(_controller, _cookieManager);
          }
          _injectOperationalShim();
          widget.onPageStarted?.call(url);
        },
        onProgress: (progress) {
          widget.onProgress?.call(progress);
          if (widget.showLoading && progress >= 100 && !_pageReady && mounted) {
            setState(() => _progress = progress);
          } else {
            _progress = progress;
          }
        },
        onPageFinished: (url) async {
          _hasLoadContent = true;
          _injectOperationalShim();
          widget.onPageFinished?.call(url);
          if (widget.showLoading && mounted) {
            setState(() {});
          }
          final title = await _controller.getTitle();
          if (title != null && title.isNotEmpty && mounted) {
            setState(() => _title = title);
          }
          if (Platform.isAndroid && _config.preventAndroidImageDrag) {
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

    // 复刻旧 webview 的 Toaster 通道：H5 postMessage 弹 SnackBar。
    if (_config.enableToaster) {
      _controller.addJavaScriptChannel(
        'Toaster',
        onMessageReceived: (msg) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(msg.message)));
          }
        },
      );
    }
    // 复刻旧 webview 的透明背景（setBackgroundColor(0x00000000)）。
    if (_config.backgroundColor != null) {
      _controller.setBackgroundColor(_config.backgroundColor!);
    }

    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      if (_config.enableWebDebugging) {
        AndroidWebViewController.enableDebugging(true);
      }
      if (_config.mediaAutoPlay) {
        platform.setMediaPlaybackRequiresUserGesture(false);
      }
      // 复刻旧 webview 的 setOnShowFileSelector：H5 `<input type=file>` 交给宿主处理。
      platform.setOnShowFileSelector((params) => widget.host.onShowFileSelector(
            WebBridgeFileSelector(
              acceptTypes: params.acceptTypes,
              allowMultiple: params.mode == FileSelectorMode.openMultiple,
            ),
          ));
    }
    if (platform is WebKitWebViewController) {
      platform.setAllowsBackForwardNavigationGestures(true);
      // 复刻旧 webview：非 release 下开启 iOS 可检查（Safari 调试）。
      if (_config.enableWebDebugging && !kReleaseMode) {
        platform.setInspectable(true);
      }
    }

    widget.onControllerCreated?.call(_controller);
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

  /// 在 `window.<channelName>` 上把运营能力注入为具名函数（login / share /
  /// savePhotoAndVideo 等），使 H5 能用 `window['<channel>'] && window['<channel>'].login`
  /// 这类「属性是否存在」的写法探测接口可用性——JavaScriptChannel 原生只暴露
  /// `postMessage`，这些方法名默认探测不到。注入的函数把调用转发回 `postMessage`
  /// 的 `{method, params, callback}` 约定，因此探测与真实调用都可用。
  ///
  /// 幂等：channel 未就绪、已注入过、或该方法已是函数时跳过，绝不覆盖既有实现。
  void _injectOperationalShim() {
    final methods = _config.operationalShimMethods;
    if (methods.isEmpty) return;
    final list = methods.map((m) => "'$m'").join(',');
    _controller.runJavaScript('''
(function(){
  var b = window['${_config.channelName}'];
  if(!b || b.__opShimInjected){ return; }
  b.__opShimInjected = true;
  var post = b.postMessage.bind(b);
  function mk(name){
    return function(params, callback){
      var p = params;
      if(typeof params === 'string'){ try{ p = JSON.parse(params); }catch(e){ p = {}; } }
      if(p == null || typeof p !== 'object'){ p = {}; }
      post(JSON.stringify({ method: name, params: p, callback: callback || '' }));
    };
  }
  [$list].forEach(function(m){ if(typeof b[m] !== 'function'){ b[m] = mk(m); } });
})();
''');
  }

  /// 启动流程：先在首帧前把宿主 UA 标识预设好，再加载真实页，
  /// 使真实内容只加载一次（不再 reload，无闪烁、无遮罩依赖）。
  Future<void> _bootstrap() async {
    await _applyUaMarker();
    await _loadContent();
  }

  /// http(s) 走 loadRequest，其余按本地 Flutter asset 加载（复刻旧 webview 行为）。
  Future<void> _loadContent() {
    if (widget.url.startsWith('http')) {
      return _controller.loadRequest(Uri.parse(widget.url));
    }
    return _controller.loadFlutterAsset(widget.url);
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
    // 内嵌模式：宿主页自带 Scaffold / AppBar 且自管返回，
    // 这里只返回 WebView 本体，不拦截返回、不套 Scaffold。
    if (widget.embedded) {
      return _body();
    }
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

  /// 复刻旧 webview：仅 iOS 关闭键盘避让 resize（规避 WPS 网页因 resize 收起输入法）。
  bool? get _resizeToAvoidBottomInset =>
      _config.avoidBottomInsetExceptIOS && Platform.isIOS ? false : null;

  Widget _content(BuildContext context) {
    if (!widget.showTitle) {
      return Scaffold(
        resizeToAvoidBottomInset: _resizeToAvoidBottomInset,
        body: _body(),
      );
    }
    return Scaffold(
      resizeToAvoidBottomInset: _resizeToAvoidBottomInset,
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
    if (_loadFail && _config.showLoadFailView) {
      Future<void> retry() async {
        _loadContent();
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
    final webView = WebViewWidget(controller: _controller);
    if (!widget.showLoading || _pageReady) {
      return webView;
    }
    return Stack(
      children: [
        webView,
        const Positioned.fill(
          child: ColoredBox(
            color: Colors.white,
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    widget.host.removeListener(_hostListener);
    super.dispose();
  }
}
