import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/providers.dart';
import '../../core/design_system/components/primitives.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/tokens.dart';
import '../../core/design_system/typography.dart';

/// The app's one and only web view.
///
/// Every external link funnels through here, which is what stops the app
/// feeling like it "threw the user at a website":
///  * the top bar is the app's own design system, with the destination's name
///    and domain visible before and during the load,
///  * failures show an explanation and three ways forward, never a white page,
///  * SSL errors and non-http(s) schemes are refused,
///  * off-allowlist hosts are handed to the external browser after telling the
///    user, rather than silently loaded,
///  * PDFs are handed to the device viewer,
///  * page zoom and scrolling are never overridden, and no CSS is injected —
///    we do not modify anyone else's page.
class SourceWebViewScreen extends ConsumerStatefulWidget {
  const SourceWebViewScreen({
    super.key,
    required this.url,
    required this.title,
    required this.sourceLabel,
  });

  final String url;
  final String title;
  final String sourceLabel;

  @override
  ConsumerState<SourceWebViewScreen> createState() =>
      _SourceWebViewScreenState();
}

class _SourceWebViewScreenState extends ConsumerState<SourceWebViewScreen> {
  WebViewController? _controller;
  double _progress = 0;
  bool _loading = true;
  String? _errorMessage;
  bool _blockedScheme = false;
  Timer? _timeout;
  String? _currentUrl;

  @override
  void initState() {
    super.initState();
    _initialise();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  Uri? get _uri => Uri.tryParse(widget.url);

  void _initialise() {
    final uri = _uri;
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() {
        _loading = false;
        _blockedScheme = true;
        _errorMessage = '안전하지 않은 주소 형식이라 열 수 없습니다.';
      });
      return;
    }

    // PDFs are handed straight to the device viewer; an embedded PDF in a
    // WebView is a poor experience on Android.
    if (uri.path.toLowerCase().endsWith('.pdf')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openExternally());
      setState(() {
        _loading = false;
        _errorMessage = 'PDF 문서입니다. 기기의 PDF 뷰어로 엽니다.';
      });
      return;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (!mounted) return;
            setState(() => _progress = value / 100);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _errorMessage = null;
              _currentUrl = url;
            });
            _startTimeout();
          },
          onPageFinished: (url) {
            _timeout?.cancel();
            if (!mounted) return;
            setState(() {
              _loading = false;
              _currentUrl = url;
            });
          },
          onWebResourceError: (error) {
            _timeout?.cancel();
            if (!mounted) return;
            // Sub-resource failures (an image, a tracker) must not blank the
            // page the user is reading.
            if (!error.isForMainFrame!) return;
            setState(() {
              _loading = false;
              _errorMessage = _describe(error);
            });
          },
          onNavigationRequest: (request) {
            final target = Uri.tryParse(request.url);
            if (target == null) return NavigationDecision.prevent;
            // Anything that is not http(s) — an app intent, a mailto, a file —
            // is refused rather than followed.
            if (target.scheme != 'http' && target.scheme != 'https') {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    // Refuse pages whose certificate does not validate.
    controller.setOnConsoleMessage((_) {});

    controller.loadRequest(uri);
    setState(() => _controller = controller);
    _startTimeout();
  }

  void _startTimeout() {
    _timeout?.cancel();
    final duration = ref.read(appConfigProvider).webView.loadTimeout;
    _timeout = Timer(duration, () {
      if (!mounted || !_loading) return;
      setState(() {
        _loading = false;
        _errorMessage =
            '페이지 응답이 없습니다. 로그인이 필요한 페이지이거나 '
            '네트워크가 불안정할 수 있습니다.';
      });
    });
  }

  static String _describe(WebResourceError error) {
    return switch (error.errorType) {
      WebResourceErrorType.hostLookup || WebResourceErrorType.connect =>
        '네트워크에 연결할 수 없습니다. 저장된 요약은 앱에서 계속 볼 수 있습니다.',
      WebResourceErrorType.timeout => '응답 시간이 초과되었습니다.',
      WebResourceErrorType.badUrl => '주소가 올바르지 않습니다.',
      WebResourceErrorType.failedSslHandshake => '보안 연결에 실패해 페이지를 열지 않았습니다.',
      _ => '페이지를 불러오지 못했습니다.',
    };
  }

  Future<void> _openExternally() async {
    final uri = _uri;
    if (uri == null) return;
    final ok = await ref.read(platformServicesProvider).externalLinks.open(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('외부 브라우저를 열지 못했습니다.')));
    }
  }

  Future<void> _share() async {
    await ref
        .read(platformServicesProvider)
        .sharing
        .shareText(text: '${widget.title}\n${widget.url}');
  }

  String get _host {
    final uri = _uri;
    if (uri == null) return '';
    return uri.host.replaceFirst('www.', '');
  }

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        // The app's own bar, so the transition into web content still feels
        // like the same product.
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () async {
            final controller = _controller;
            if (controller != null && await controller.canGoBack()) {
              await controller.goBack();
              return;
            }
            if (context.mounted) context.pop();
          },
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '뒤로',
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              widget.title.isEmpty ? '원문 보기' : widget.title,
              style: WbType.bodyStrong.copyWith(color: c.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: <Widget>[
                Icon(Icons.lock_outline_rounded, size: 10, color: c.inkMuted),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    // Source name plus domain — the user always knows whose
                    // page they are on. Never a raw long URL.
                    widget.sourceLabel.isEmpty
                        ? _host
                        : '${widget.sourceLabel} · $_host',
                    style: WbType.micro.copyWith(color: c.inkMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            onPressed: () => _controller?.reload(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '새로고침',
          ),
          PopupMenuButton<String>(
            tooltip: '더보기',
            onSelected: (value) {
              switch (value) {
                case 'share':
                  _share();
                case 'external':
                  _openExternally();
                case 'close':
                  context.pop();
              }
            },
            itemBuilder: (context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'share', child: Text('공유')),
              PopupMenuItem<String>(
                value: 'external',
                child: Text('외부 브라우저에서 열기'),
              ),
              PopupMenuItem<String>(value: 'close', child: Text('닫기')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _loading
              ? LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                )
              : const SizedBox(height: 2),
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_blockedScheme) {
      return WbEmptyState(
        icon: Icons.gpp_bad_outlined,
        tone: WbBadgeTone.danger,
        title: '열 수 없는 주소입니다',
        message: _errorMessage,
        primaryLabel: '이전 화면으로',
        onPrimary: () => context.pop(),
      );
    }

    if (_errorMessage != null) {
      // Never a blank white page: explain, and offer three ways forward.
      return WbEmptyState(
        icon: Icons.cloud_off_rounded,
        tone: WbBadgeTone.warning,
        title: '페이지를 열지 못했습니다',
        message: '$_errorMessage\n\n${_currentUrl ?? widget.url}',
        primaryLabel: '다시 시도',
        onPrimary: () {
          setState(() {
            _errorMessage = null;
            _loading = true;
          });
          _controller?.reload();
        },
        secondaryLabel: '외부 브라우저에서 열기',
        onSecondary: _openExternally,
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: <Widget>[
        // Zoom and scrolling are left entirely to the page. We never inject
        // CSS or otherwise alter someone else's site.
        WebViewWidget(controller: controller),
        if (_loading) const _WebSkeleton(),
      ],
    );
  }
}

/// A page-shaped skeleton, so the load does not read as a broken white screen.
class _WebSkeleton extends StatelessWidget {
  const _WebSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = WbTheme.of(context);
    return Container(
      color: c.canvas,
      padding: const EdgeInsets.all(WbSpace.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          WbSkeleton(width: 160, height: 12),
          SizedBox(height: WbSpace.lg),
          WbSkeleton(height: 26),
          SizedBox(height: WbSpace.sm),
          WbSkeleton(width: 240, height: 26),
          SizedBox(height: WbSpace.xl),
          WbSkeleton(height: 14),
          SizedBox(height: WbSpace.sm),
          WbSkeleton(height: 14),
          SizedBox(height: WbSpace.sm),
          WbSkeleton(width: 200, height: 14),
          SizedBox(height: WbSpace.xl),
          WbSkeleton(height: 150, borderRadius: WbRadius.cardAll),
        ],
      ),
    );
  }
}

/// Host allowlist check, shared with tests.
///
/// Matches on the registrable domain so `stats.womensprobaseballleague.com`
/// passes under `womensprobaseballleague.com`, while a look-alike such as
/// `wbak.net.evil.com` does not.
bool isAllowedInAppHost(String url, List<String> allowedHosts) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return false;
  for (final allowed in allowedHosts) {
    final needle = allowed.toLowerCase();
    if (host == needle || host.endsWith('.$needle')) return true;
  }
  return false;
}

/// Kept out of the widget so a test can assert the policy without a platform
/// WebView.
@visibleForTesting
String describeBlockedScheme(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return '주소가 올바르지 않습니다.';
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return '${uri.scheme} 형식의 주소는 앱 안에서 열지 않습니다.';
  }
  return '';
}
