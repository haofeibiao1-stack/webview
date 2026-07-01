import 'package:flutter/material.dart';

/// 内置的加载失败视图。宿主可通过 WebBridgeConfig.loadFailBuilder 替换。
class DefaultLoadFailView extends StatelessWidget {
  final Future<void> Function() retry;

  const DefaultLoadFailView({super.key, required this.retry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 48, color: Color(0xFFa29ea7)),
          const SizedBox(height: 12),
          const Text('网页加载异常，请刷新页面重试',
              style: TextStyle(fontSize: 13, color: Color(0xFFa29ea7))),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: retry,
            child: Container(
              width: 64,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                color: const Color(0xFFf1f4ff),
                border: Border.all(color: const Color(0xFFb0c1ff), width: 1),
              ),
              child: const Center(
                child: Text('刷新',
                    style: TextStyle(fontSize: 13, color: Color(0xFF5257ef))),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
