import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'restriction_appeal_service.dart';

/// The notice a restricted customer sees (catalog banner and checkout).
///
/// It explains the restriction AND carries the clickable appeal link:
///   - never appealed      -> "Appeal this restriction"
///   - appeal waiting      -> "Appeal sent..." + "View my appeal"
///   - appeal denied       -> "not approved..." + "Send a new appeal" (or the
///                            date they may appeal again)
/// Tapping the link opens a sheet where the customer writes the appeal. An
/// admin then reads it in the Fraud Activity Log and approves or denies it
/// (server: fraud_appeal.php). On approval the restriction is lifted and the
/// screens reopen by themselves, because they watch the customer's document.
///
/// The parent only shows this when it already knows the account is
/// restricted (its own Firestore listener), so the card never has to guess:
/// while the server answer is loading, or if it fails, the link is still
/// shown and the sheet loads the status itself.
class RestrictionNotice extends StatefulWidget {
  /// Text like "for the next 29 days" (null = "for 30 days").
  final String? untilText;

  /// One short card for the catalog. Not compact = the full checkout card.
  final bool compact;

  /// Shows an X when set (catalog banner). Null = no X (checkout).
  final VoidCallback? onDismiss;

  const RestrictionNotice({
    super.key,
    this.untilText,
    this.compact = false,
    this.onDismiss,
  });

  @override
  State<RestrictionNotice> createState() => _RestrictionNoticeState();
}

class _RestrictionNoticeState extends State<RestrictionNotice> {
  final RestrictionAppealService _service = RestrictionAppealService();
  RestrictionAppealStatus? _status; // null = still loading / could not load

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await _service.fetchStatus();
      if (mounted) setState(() => _status = status);
    } catch (e) {
      // Not fatal: the link still works, the sheet retries on its own.
      debugPrint('RestrictionNotice: status load failed: $e');
    }
  }

  Future<void> _openAppeal() async {
    await showRestrictionAppealSheet(context, service: _service, initial: _status);
    // Whatever happened in the sheet (sent / closed), read the latest.
    if (mounted) _loadStatus();
  }

  /// The small sentence about the appeal, and the words of the link.
  ({String? note, String link}) _appealTexts() {
    final s = _status;
    if (s == null) return (note: null, link: 'Appeal this restriction');
    if (s.isPending) {
      return (note: 'Appeal sent. An admin is reviewing it.', link: 'View my appeal');
    }
    if (s.isDenied && !s.canAppeal) {
      final when = s.canAppealAt;
      final text = when == null
          ? 'Your last appeal was not approved.'
          : 'Your last appeal was not approved. You can appeal again on ${DateFormat('MMM d, h:mm a').format(when)}.';
      return (note: text, link: 'View my appeal');
    }
    if (s.isDenied) {
      return (note: 'Your last appeal was not approved.', link: 'Send a new appeal');
    }
    return (note: null, link: 'Appeal this restriction');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = widget.compact;
    final until = widget.untilText ?? 'for 30 days';
    final texts = _appealTexts();

    // Catalog = red (matches the old banner); checkout = amber.
    final Color accent = compact ? Colors.red : Colors.amber;
    final Color background = compact
        ? (isDark ? const Color(0xFF3A1418) : const Color(0xFFFDF0F0))
        : Colors.amber.withOpacity(isDark ? 0.15 : 0.1);
    final Color border = compact
        ? (isDark ? Colors.red[300]! : Colors.red[200]!).withOpacity(0.5)
        : Colors.amber.withOpacity(0.4);
    final Color titleColor = compact
        ? (isDark ? Colors.red[200]! : Colors.red[900]!)
        : (isDark ? Colors.amber[200]! : Colors.amber[900]!);
    final Color bodyColor = compact
        ? (isDark ? Colors.red[100]! : Colors.red[700]!)
        : (isDark ? Colors.amber[100]! : Colors.amber[800]!);
    final Color linkColor = compact
        ? (isDark ? Colors.red[200]! : Colors.red[800]!)
        : (isDark ? Colors.amber[200]! : const Color(0xFF8A5A00));

    return Container(
      width: double.infinity,
      margin: compact ? const EdgeInsets.fromLTRB(16, 10, 16, 0) : EdgeInsets.zero,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 14 : 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(compact ? 20 : 18),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withOpacity(isDark ? 0.2 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              compact ? Icons.shield_rounded : Icons.warning_amber_rounded,
              color: compact ? (isDark ? Colors.red[300] : Colors.red[600]) : Colors.amber,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  compact ? 'ACCOUNT RESTRICTED' : 'Account Restricted - Ordering Paused',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 11 : 12,
                    letterSpacing: compact ? 0.2 : 0,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  compact
                      ? 'Your account was restricted $until. You can\'t place orders until an admin approves your appeal.'
                      : 'This account is restricted $until following a review of recent account activity. '
                      'Every payment method is turned off, so you can\'t place an order right now. '
                      'You can order again once an admin approves your appeal.',
                  style: TextStyle(
                    fontSize: compact ? 11.5 : 11,
                    fontWeight: compact ? FontWeight.w600 : FontWeight.normal,
                    color: bodyColor,
                  ),
                ),
                if (texts.note != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    texts.note!,
                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: bodyColor),
                  ),
                ],
                const SizedBox(height: 4),
                // THE CLICKABLE APPEAL TEXT. InkWell gives the tap + ripple;
                // the padding makes the touch area big enough for a thumb.
                InkWell(
                  onTap: _openAppeal,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      texts.link,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: linkColor,
                        decoration: TextDecoration.underline,
                        decorationColor: linkColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.onDismiss != null)
            InkWell(
              onTap: widget.onDismiss,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close_rounded,
                    size: 18, color: isDark ? Colors.red[300] : Colors.red[400]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens the appeal sheet. Returns true when an appeal was sent.
Future<bool?> showRestrictionAppealSheet(
    BuildContext context, {
      required RestrictionAppealService service,
      RestrictionAppealStatus? initial,
    }) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true, // lets the sheet rise above the keyboard
    backgroundColor: Colors.transparent,
    builder: (_) => _AppealSheet(service: service, initial: initial),
  );
}

class _AppealSheet extends StatefulWidget {
  final RestrictionAppealService service;
  final RestrictionAppealStatus? initial;

  const _AppealSheet({required this.service, this.initial});

  @override
  State<_AppealSheet> createState() => _AppealSheetState();
}

class _AppealSheetState extends State<_AppealSheet> {
  final TextEditingController _controller = TextEditingController();
  RestrictionAppealStatus? _status;
  bool _loading = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.initial;
    // The card may not have loaded the status yet (or it failed): load it now.
    if (_status == null) _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.service.fetchStatus();
      if (mounted) setState(() => _status = s);
    } on RestrictionAppealException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _min => _status?.minChars ?? 20;
  int get _max => _status?.maxChars ?? 1000;
  int get _length => _controller.text.trim().length;
  bool get _lengthOk => _length >= _min && _length <= _max;

  Future<void> _send() async {
    if (!_lengthOk || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.service.submit(_controller.text.trim());
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Your appeal was sent. An admin will review it.'),
          backgroundColor: Colors.green,
        ),
      );
    } on RestrictionAppealException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
      });
      // The server knows better than our copy of the status (a pending
      // appeal, a cooldown, a lifted restriction): refresh so the sheet
      // shows the real situation instead of a form that will fail again.
      if (const ['ALREADY_PENDING', 'COOLDOWN', 'NOT_RESTRICTED'].contains(e.code)) {
        _load();
      }
    }
  }

  String _dateText(DateTime? d) =>
      d == null ? '' : DateFormat('MMM d, yyyy · h:mm a').format(d);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paper = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final primary = isDark ? Colors.white : Colors.black87;
    final secondary = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    const amber = Color(0xFFF4B400);
    final s = _status;

    // What the sheet shows depends on the server's answer.
    Widget body;
    if (_loading && s == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: amber)),
      );
    } else if (s == null) {
      // Could not load at all: say why and let them retry.
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_error ?? 'Could not load your appeal. Please try again.',
              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: const Text('TRY AGAIN')),
        ],
      );
    } else if (!s.restricted) {
      body = Text(
        'Your account is not restricted right now, so there is nothing to appeal. '
            'If you still can\'t order, please close this and try again in a moment.',
        style: TextStyle(fontSize: 13, color: secondary),
      );
    } else if (s.isPending || (s.isDenied && !s.canAppeal)) {
      // Read-only view of the appeal already sent.
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusChip(
            s.isPending ? 'WAITING FOR REVIEW' : 'NOT APPROVED',
            s.isPending ? amber : Colors.redAccent,
            isDark,
          ),
          const SizedBox(height: 12),
          Text('Your appeal', style: TextStyle(fontWeight: FontWeight.bold, color: primary)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF262626) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(s.appealMessage, style: TextStyle(fontSize: 13, color: primary)),
          ),
          if (s.submittedAt != null) ...[
            const SizedBox(height: 8),
            Text('Sent ${_dateText(s.submittedAt)}',
                style: TextStyle(fontSize: 11, color: secondary)),
          ],
          const SizedBox(height: 10),
          Text(
            s.isPending
                ? 'An admin will review it. You will be able to order again as soon as it is approved.'
                : (s.canAppealAt != null
                ? 'You can send a new appeal on ${_dateText(s.canAppealAt)}.'
                : 'You can send a new appeal later.'),
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ],
      );
    } else {
      // The form (first appeal, or a new one after a denial).
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s.isDenied) ...[
            _statusChip('LAST APPEAL NOT APPROVED', Colors.redAccent, isDark),
            const SizedBox(height: 10),
          ],
          Text(
            'Tell the shop why this restriction should be lifted. An admin will read it '
                'and decide. Be specific: what happened, and why it will not happen again.',
            style: TextStyle(fontSize: 12.5, color: secondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            enabled: !_sending,
            maxLines: 6,
            minLines: 4,
            maxLength: _max,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}), // refreshes the counter + button
            style: TextStyle(color: primary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Write your appeal here...',
              helperText: _length < _min ? 'At least $_min characters ($_length so far)' : null,
              filled: true,
              fillColor: isDark ? const Color(0xFF262626) : const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: (_lengthOk && !_sending) ? _send : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: amber,
                foregroundColor: Colors.black,
                disabledBackgroundColor: amber.withOpacity(0.35),
                disabledForegroundColor: Colors.black54,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
              child: _sending
                  ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('SEND APPEAL'),
            ),
          ),
        ],
      );
    }

    return Padding(
      // viewInsets.bottom = the keyboard's height, so the form stays visible.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[700] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Appeal your restriction',
                    style: GoogleFonts.cormorantGaramond(
                        fontSize: 26, fontWeight: FontWeight.bold, color: primary)),
                const SizedBox(height: 12),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String text, Color color, bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.2 : 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }
}