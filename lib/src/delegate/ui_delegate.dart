import 'package:flutter/material.dart';

/// UI 适配层：Loading 与 Toast 的展示交给宿主，保证与各 App 视觉一致。
abstract class WebBridgeUiDelegate {
  void showLoading(BuildContext context);

  void dismissLoading();

  void showToast(
    BuildContext context,
    String message, {
    String? action,
    VoidCallback? onClick,
  });
}

/// 默认 UI 实现：OverlayEntry 菊花 + 悬浮 SnackBar。宿主可替换为自有样式。
class DefaultUiDelegate implements WebBridgeUiDelegate {
  OverlayEntry? _overlayEntry;
  bool _isVisible = false;

  @override
  void showLoading(BuildContext context) {
    if (_isVisible || _overlayEntry != null) return;
    _isVisible = true;
    _overlayEntry = OverlayEntry(
      builder: (_) => const Material(
        color: Colors.black54,
        child: Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  void dismissLoading() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isVisible = false;
  }

  @override
  void showToast(
    BuildContext context,
    String message, {
    String? action,
    VoidCallback? onClick,
  }) {
    if (!context.mounted) return;
    final bool hasAction =
        action != null && action.isNotEmpty && onClick != null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 80),
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        content: Container(
          margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xE6161724),
            borderRadius: BorderRadius.circular(12),
          ),
          child: hasAction
              ? Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 12),
                        child: Text(
                          message,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 12),
                      child: GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          onClick();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            action,
                            style: const TextStyle(
                                color: Colors.black, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 12),
                    child: Text(
                      message,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
        ),
        duration: Duration(seconds: hasAction ? 3 : 1),
      ),
    );
  }
}
