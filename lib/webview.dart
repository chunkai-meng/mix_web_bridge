import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import './inner_bridge.dart';
import './manager.dart';

const notFoundHtml = r'''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <meta name="viewport" content="width=device-width,minimum-scale=1.0,initial-scale=1.0,maximum-scale=1.0,user-scalable=no,viewport-fit=cover" />
    <meta name="format-detection" content="telephone=no">
    <meta name="wap-font-scale" content="no">
    <title>404</title>
  </head>
  <body style="text-align: center;">
    <div style="margin: 12px 0; font-size: 18px;">404 Not Found</div>
    <a style="text-decoration: none;" href="javascript:$app.route({pop: true});">Back</a>
  </body>
</html>
''';

class MixWebViewArgs {
  final String? initialUrl;
  final String? initialHtml;
  late final JavascriptMode javascriptMode;
  late final String? userAgent;
  late final JavascriptChannel bridgeChannel;
  late final WebViewCreatedCallback onWebViewCreated;

  MixWebViewArgs({required MixWebBridgeManager bridgeManager, required this.initialUrl, this.initialHtml}) {
    javascriptMode = JavascriptMode.unrestricted;
    userAgent = bridgeManager.injectedJsToUserAgent();
    bridgeChannel = JavascriptChannel(
      name: bridgeManager.channelName,
      onMessageReceived: (msg) => bridgeManager.onChannelMessageReceived(msg.message),
    );
    onWebViewCreated = (vc) {
      bridgeManager.jsRunner = vc.runJavascriptReturningResult;
      final html = initialHtml;
      final url = initialUrl ?? "";
      if (html != null) {
        vc.loadHtmlString(html);
      } else if (url.isEmpty) {
        vc.loadHtmlString(notFoundHtml);
      }
    };
  }
}

abstract class MixWebViewState<T extends StatefulWidget> extends State<T> with RouteAware, WidgetsBindingObserver {
  final MixWebBridgeManager bridgeManager = MixWebBridgeManager();
  bool _onTop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance?.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    mwbRouteObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_onTop) return;
    if (state == AppLifecycleState.resumed) {
      bridgeManager.callEvent("appResumed");
    } else if (state == AppLifecycleState.paused) {
      bridgeManager.callEvent("appPaused");
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  void dispose() {
    mwbRouteObserver.unsubscribe(this);
    WidgetsBinding.instance?.removeObserver(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _onTop = true;
    bridgeManager.callEvent("pageAppear");
  }

  @override
  void didPushNext() {
    _onTop = false;
    bridgeManager.callEvent("pageDisappear");
  }

  void didGetTitle(String title) {}

  Widget buildWebView({required String? url, String? html}) {
    MixWebViewArgs args = MixWebViewArgs(bridgeManager: bridgeManager, initialUrl: url, initialHtml: url);
    return WebView(
      initialUrl: args.initialUrl,
      javascriptMode: args.javascriptMode,
      userAgent: args.userAgent,
      javascriptChannels: {args.bridgeChannel},
      onWebViewCreated: args.onWebViewCreated,
      onPageFinished: (url) async {
        final title = await bridgeManager.runJs("document.title");
        didGetTitle(title ?? "");
      },
    );
  }
}
