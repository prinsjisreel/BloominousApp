import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// How the in-app payment page ended.
///  - success   : the payment site sent us back to the shop (or flowerar://success)
///  - cancelled : the payment site sent us back with a cancel/fail address
///  - closed    : the customer closed the page by hand (we don't know the result)
enum PaymentCheckoutResult { success, cancelled, closed }

/// Shows the PayMongo checkout (GCash / Maya) INSIDE the app, so the customer
/// never gets thrown out to the phone's browser.
///
/// Input : the `checkoutUrl` returned by PaymentService.startOrderPayment.
/// Output: pops with a [PaymentCheckoutResult]. The caller then double-checks
///         the real payment status in Firestore (a WebView can't be trusted
///         to know whether money actually moved).
class PaymentCheckoutPage extends StatefulWidget {
  final String checkoutUrl;
  final String title;

  const PaymentCheckoutPage({
    super.key,
    required this.checkoutUrl,
    this.title = 'Secure Payment',
  });

  @override
  State<PaymentCheckoutPage> createState() => _PaymentCheckoutPageState();
}

class _PaymentCheckoutPageState extends State<PaymentCheckoutPage> {
  // Our own shop site. When the payment provider redirects here, the
  // payment step is over and we should leave the WebView.
  static const String _shopHost = 'honeydew-duck-132160.hostingersite.com';

  late final WebViewController _controller;
  int _progress = 0;
  bool _loadFailed = false;
  bool _finished = false; // true once we've decided the result

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _loadFailed = false);
          },
          onWebResourceError: (error) {
            // Only the main page matters; broken images/trackers are ignored.
            if (error.isForMainFrame == true && mounted) {
              setState(() => _loadFailed = true);
            }
          },
          onNavigationRequest: _handleNavigation,
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  /// Runs BEFORE every page change. We decide: let it load, hand it to
  /// another app (GCash/Maya), or treat it as "payment finished".
  Future<NavigationDecision> _handleNavigation(NavigationRequest request) async {
    if (_finished) return NavigationDecision.prevent;

    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;
    final scheme = uri.scheme.toLowerCase();

    // 1) Legacy deep links used by the older payment code.
    if (scheme == 'flowerar') {
      final ok = !(uri.host.contains('cancel') || uri.path.contains('cancel'));
      _finish(ok ? PaymentCheckoutResult.success : PaymentCheckoutResult.cancelled);
      return NavigationDecision.prevent;
    }

    // 2) Harmless internal schemes stay inside the WebView.
    if (const ['about', 'data', 'blob', 'javascript', 'file'].contains(scheme)) {
      return NavigationDecision.navigate;
    }

    // 3) Other non-web schemes (gcash://, maya://, intent://) are app
    //    deep links. A WebView can't open them, so hand them to the phone.
    if (scheme != 'http' && scheme != 'https') {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('PaymentCheckoutPage: could not open $scheme link: $e');
      }
      return NavigationDecision.prevent;
    }

    // 4) Back on our own site = the provider sent the customer home.
    if (uri.host == _shopHost) {
      final lower = request.url.toLowerCase();
      final cancelled = lower.contains('cancel') || lower.contains('fail');
      _finish(cancelled ? PaymentCheckoutResult.cancelled : PaymentCheckoutResult.success);
      return NavigationDecision.prevent;
    }

    // 5) Everything else (PayMongo, GCash/Maya web login) loads normally.
    return NavigationDecision.navigate;
  }

  void _finish(PaymentCheckoutResult result) {
    if (_finished) return;
    _finished = true;
    if (mounted) Navigator.of(context).pop(result);
  }

  /// Back button / X: ask first, because leaving mid-payment is easy to
  /// do by accident.
  Future<void> _confirmClose() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Leave payment?', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
          'If you already paid, your order will update shortly. '
          'If not, your order stays saved under To Pay.',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('STAY'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('LEAVE'),
          ),
        ],
      ),
    );
    if (leave == true) _finish(PaymentCheckoutResult.closed);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false, // we control every exit so the caller always gets a result
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Go back inside the payment site first, then offer to leave.
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          await _confirmClose();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _confirmClose,
          ),
          bottom: _progress < 100 && !_loadFailed
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(value: _progress / 100, minHeight: 3),
                )
              : null,
        ),
        // SafeArea keeps the page above the phone's gesture/nav bar.
        body: SafeArea(
          child: _loadFailed
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_off_rounded, size: 56, color: isDark ? Colors.white54 : Colors.black45),
                        const SizedBox(height: 16),
                        Text('The payment page could not load.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text('Check your connection and try again. Your order is already saved.',
                            textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 12)),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            setState(() => _loadFailed = false);
                            _controller.loadRequest(Uri.parse(widget.checkoutUrl));
                          },
                          child: const Text('TRY AGAIN'),
                        ),
                      ],
                    ),
                  ),
                )
              : WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}
