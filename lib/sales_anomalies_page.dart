import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'app_sidebar.dart';

const Map<String, String> _typeLabels = {
  'value_spike': 'Statistical Threshold Spike',
  'void_spike': 'Void/Cancellation Spike',
  'excessive_discount': 'Excessive Discount',
  'off_hours': 'Off-Hours Activity',
};

class SalesAnomaliesPage extends StatefulWidget {
  final String role;
  const SalesAnomaliesPage({super.key, this.role = 'employee'});

  @override
  State<SalesAnomaliesPage> createState() => _SalesAnomaliesPageState();
}

class _SalesAnomaliesPageState extends State<SalesAnomaliesPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _severityFilter = 'all';

  // NEW: peakAvgMultiplier / peakCriticalMultiplier added alongside the
  // original numeric fields — same settings/anomaly_config document the
  // web dashboard now writes these two keys to.
  final Map<String, TextEditingController> _controllers = {
    'avgMultiplier': TextEditingController(),
    'criticalMultiplier': TextEditingController(),
    'minBaselineTransactions': TextEditingController(),
    'fallbackHighValueThreshold': TextEditingController(),
    'peakAvgMultiplier': TextEditingController(),
    'peakCriticalMultiplier': TextEditingController(),
    'voidWindowHours': TextEditingController(),
    'voidCountMedium': TextEditingController(),
    'voidCountCritical': TextEditingController(),
    'discountMediumPercent': TextEditingController(),
    'discountCriticalPercent': TextEditingController(),
  };

  final Map<String, FocusNode> _focusNodes = {
    'avgMultiplier': FocusNode(),
    'criticalMultiplier': FocusNode(),
    'minBaselineTransactions': FocusNode(),
    'fallbackHighValueThreshold': FocusNode(),
    'peakAvgMultiplier': FocusNode(),
    'peakCriticalMultiplier': FocusNode(),
    'voidWindowHours': FocusNode(),
    'voidCountMedium': FocusNode(),
    'voidCountCritical': FocusNode(),
    'discountMediumPercent': FocusNode(),
    'discountCriticalPercent': FocusNode(),
  };

  // NEW: peakDates is a multi-line date-range list, not a single number —
  // it gets its own controller/focus node rather than living in the
  // numeric maps above.
  final TextEditingController _peakDatesController = TextEditingController();
  final FocusNode _peakDatesFocus = FocusNode();

  bool get _anyFieldFocused =>
      _focusNodes.values.any((f) => f.hasFocus) || _peakDatesFocus.hasFocus;

  String _storeOpenTime24 = '08:00';
  String _storeCloseTime24 = '20:00';
  bool _isLoadingThresholds = true;
  bool _saving = false;

  StreamSubscription<DocumentSnapshot>? _configSub;

  @override
  void initState() {
    super.initState();
    _listenToConfig();
  }

  @override
  void dispose() {
    _configSub?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    _peakDatesController.dispose();
    _peakDatesFocus.dispose();
    super.dispose();
  }

  String _to12HourDisplay(String hhmm24) {
    final parts = hhmm24.split(':');
    final hour = int.tryParse(parts[0]) ?? 8;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final now = DateTime.now();
    return DateFormat('hh:mm a').format(DateTime(now.year, now.month, now.day, hour, minute));
  }

  String _to24HourString(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  // NEW: turns the textarea's "2026-02-10 to 2026-02-15" lines into the
  // {start, end} map shape the web engine's checkValueSpike() expects.
  // Mirrors sales_anomalies.js's parsePeakDatesText() exactly, so a range
  // typed in the app reads back correctly on web and vice versa.
  List<Map<String, String>> _parsePeakDatesText(String text) {
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) {
      final parts = line.split(RegExp(r'\s+to\s+', caseSensitive: false)).map((p) => p.trim()).toList();
      final start = parts.isNotEmpty ? parts[0] : '';
      final end = parts.length > 1 ? parts[1] : start;
      return {'start': start, 'end': end};
    })
        .where((r) => (r['start'] ?? '').isNotEmpty && (r['end'] ?? '').isNotEmpty)
        .toList();
  }

  // The reverse of the above — turns the stored array back into editable
  // textarea lines.
  String _peakDatesToText(List<dynamic>? ranges) {
    if (ranges == null) return '';
    return ranges.map((r) {
      final map = r as Map<String, dynamic>;
      return '${map['start'] ?? ''} to ${map['end'] ?? ''}';
    }).join('\n');
  }

  void _listenToConfig() {
    _configSub = _db.collection('settings').doc('anomaly_config').snapshots().listen((doc) {
      if (_anyFieldFocused) return;

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _controllers['avgMultiplier']!.text = (data['avgMultiplier'] ?? 5).toString();
        _controllers['criticalMultiplier']!.text = (data['criticalMultiplier'] ?? 10).toString();
        _controllers['minBaselineTransactions']!.text = (data['minBaselineTransactions'] ?? 5).toString();
        _controllers['fallbackHighValueThreshold']!.text = (data['fallbackHighValueThreshold'] ?? 5000).toString();
        _controllers['peakAvgMultiplier']!.text = (data['peakAvgMultiplier'] ?? 8).toString();
        _controllers['peakCriticalMultiplier']!.text = (data['peakCriticalMultiplier'] ?? 15).toString();
        _peakDatesController.text = _peakDatesToText(data['peakDates'] as List<dynamic>?);
        _controllers['voidWindowHours']!.text = (data['voidWindowHours'] ?? 24).toString();
        _controllers['voidCountMedium']!.text = (data['voidCountMedium'] ?? 2).toString();
        _controllers['voidCountCritical']!.text = (data['voidCountCritical'] ?? 4).toString();
        _controllers['discountMediumPercent']!.text = (data['discountMediumPercent'] ?? 15).toString();
        _controllers['discountCriticalPercent']!.text = (data['discountCriticalPercent'] ?? 30).toString();

        _storeOpenTime24 = data['storeOpenTime'] ?? '08:00';
        _storeCloseTime24 = data['storeCloseTime'] ?? '20:00';
      }
      if (mounted) setState(() => _isLoadingThresholds = false);
    }, onError: (e) {
      debugPrint('Error listening to anomaly_config: $e');
      if (mounted) setState(() => _isLoadingThresholds = false);
    });
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    try {
      final newConfig = {
        'avgMultiplier': double.tryParse(_controllers['avgMultiplier']!.text) ?? 5.0,
        'criticalMultiplier': double.tryParse(_controllers['criticalMultiplier']!.text) ?? 10.0,
        'minBaselineTransactions': int.tryParse(_controllers['minBaselineTransactions']!.text) ?? 5,
        'fallbackHighValueThreshold': double.tryParse(_controllers['fallbackHighValueThreshold']!.text) ?? 5000.0,
        'peakAvgMultiplier': double.tryParse(_controllers['peakAvgMultiplier']!.text) ?? 8.0,
        'peakCriticalMultiplier': double.tryParse(_controllers['peakCriticalMultiplier']!.text) ?? 15.0,
        'peakDates': _parsePeakDatesText(_peakDatesController.text),
        'voidWindowHours': double.tryParse(_controllers['voidWindowHours']!.text) ?? 24.0,
        'voidCountMedium': int.tryParse(_controllers['voidCountMedium']!.text) ?? 2,
        'voidCountCritical': int.tryParse(_controllers['voidCountCritical']!.text) ?? 4,
        'discountMediumPercent': double.tryParse(_controllers['discountMediumPercent']!.text) ?? 15.0,
        'discountCriticalPercent': double.tryParse(_controllers['discountCriticalPercent']!.text) ?? 30.0,
        'storeOpenTime': _storeOpenTime24,
        'storeCloseTime': _storeCloseTime24,
      };
      await _db.collection('settings').doc('anomaly_config').set(newConfig, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved and synced to web.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving settings: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(bool isOpen) async {
    final current = isOpen ? _storeOpenTime24 : _storeCloseTime24;
    final parts = current.split(':');
    final initial = TimeOfDay(hour: int.tryParse(parts[0]) ?? 8, minute: int.tryParse(parts[1]) ?? 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      if (isOpen) {
        _storeOpenTime24 = _to24HourString(picked);
      } else {
        _storeCloseTime24 = _to24HourString(picked);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.withValues(alpha: 0.2);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final isDesktop = MediaQuery.of(context).size.width >= 850;
    final isAdmin = widget.role == 'admin' || widget.role == 'super-admin';

    return Scaffold(
      backgroundColor: bgColor,
      drawer: isDesktop ? null : Drawer(child: AppSidebar(role: widget.role, currentPage: 'anomalies')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) AppSidebar(role: widget.role, currentPage: 'anomalies'),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  if (!isDesktop)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                      child: Row(
                        children: [
                          Builder(builder: (ctx) => IconButton(
                            icon: Icon(Icons.menu, color: textColor),
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          )),
                          Text('Sales Anomalies',
                              style: GoogleFonts.cormorantGaramond(color: textColor, fontWeight: FontWeight.bold, fontSize: 22)),
                        ],
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _db.collection('salesAnomalies').orderBy('timestamp', descending: true).limit(300).snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(child: Text('Error loading anomalies: ${snapshot.error}', style: TextStyle(color: textColor)));
                        }
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)));
                        }

                        final docs = snapshot.data?.docs ?? [];
                        final all = docs.map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id}).toList();

                        int critical = all.where((a) => a['severity'] == 'critical').length;
                        int medium = all.where((a) => a['severity'] == 'medium').length;
                        int low = all.where((a) => a['severity'] == 'low').length;

                        final filtered = _severityFilter == 'all'
                            ? all
                            : all.where((a) => a['severity'] == _severityFilter).toList();

                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sales Anomalies Detection',
                                style: GoogleFonts.cormorantGaramond(
                                    fontSize: isDesktop ? 32 : 24, fontWeight: FontWeight.bold, color: textColor),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Internal transactional irregularity monitoring — value spikes, void frequency, excessive discounts, off-hours activity.',
                                style: TextStyle(fontSize: 12, color: subTextColor),
                              ),
                              const SizedBox(height: 20),

                              LayoutBuilder(builder: (context, constraints) {
                                final cardWidth = constraints.maxWidth < 600
                                    ? (constraints.maxWidth - 12) / 2
                                    : (constraints.maxWidth - 36) / 4;
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    _statBox('TOTAL FLAGGED', '${all.length}', textColor, subTextColor, cardColor, borderColor, cardWidth),
                                    _statBox('CRITICAL', '$critical', Colors.red, subTextColor, cardColor, borderColor, cardWidth),
                                    _statBox('MEDIUM', '$medium', Colors.amber[800]!, subTextColor, cardColor, borderColor, cardWidth),
                                    _statBox('LOW', '$low', Colors.green[700]!, subTextColor, cardColor, borderColor, cardWidth),
                                  ],
                                );
                              }),
                              const SizedBox(height: 20),

                              Wrap(
                                spacing: 8,
                                children: [
                                  _filterChip('All', 'all', isDark, textColor),
                                  _filterChip('Critical', 'critical', isDark, textColor),
                                  _filterChip('Medium', 'medium', isDark, textColor),
                                  _filterChip('Low', 'low', isDark, textColor),
                                ],
                              ),
                              const SizedBox(height: 20),

                              if (filtered.isEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 50),
                                  alignment: Alignment.center,
                                  child: Text('No anomalies in this view.', style: TextStyle(color: subTextColor, fontStyle: FontStyle.italic)),
                                )
                              else
                                ...filtered.map((a) => _anomalyCard(a, isDark, cardColor, borderColor, textColor, subTextColor)),

                              if (isAdmin) ...[
                                const SizedBox(height: 32),
                                _buildConfigSection(isDark, cardColor, borderColor, textColor, subTextColor),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, Color valueColor, Color subTextColor, Color cardColor, Color borderColor, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: subTextColor, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value, bool isDark, Color textColor) {
    final selected = _severityFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _severityFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF111827) : (isDark ? Colors.grey[900] : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? const Color(0xFF111827) : Colors.grey.withValues(alpha: 0.25)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: selected ? Colors.white : textColor),
        ),
      ),
    );
  }

  Color _severityColor(String? severity) {
    switch (severity) {
      case 'critical':
        return Colors.red;
      case 'medium':
        return Colors.amber[800]!;
      default:
        return Colors.green[700]!;
    }
  }

  Widget _anomalyCard(Map<String, dynamic> a, bool isDark, Color cardColor, Color borderColor, Color textColor, Color subTextColor) {
    final severity = (a['severity'] ?? 'low').toString();
    final color = _severityColor(severity);
    final type = (a['type'] ?? '').toString();
    final label = _typeLabels[type] ?? type;
    final detail = (a['detail'] ?? '').toString();
    final cashierEmail = a['cashierEmail'];
    final branchId = a['branchId'];
    final invoiceId = a['invoiceId'];
    final justification = a['justificationNote'];
    final overriddenBy = a['overriddenBy'];

    final ts = a['timestamp'];
    String timeStr = '...';
    if (ts is Timestamp) {
      final d = ts.toDate();
      timeStr = '${d.month}/${d.day}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(18), border: Border.all(color: borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(severity.toUpperCase(),
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: subTextColor)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(detail, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
          const SizedBox(height: 6),
          Text(
            [
              if (cashierEmail != null) 'Staff: $cashierEmail',
              'Branch: ${branchId ?? 'n/a'}',
              if (invoiceId != null) 'Invoice: $invoiceId',
            ].join('  •  '),
            style: TextStyle(fontSize: 11, color: subTextColor),
          ),
          const SizedBox(height: 4),
          Text(timeStr, style: TextStyle(fontSize: 10, color: subTextColor, fontFamily: 'monospace')),
          if (justification != null) ...[
            const SizedBox(height: 6),
            Text('Note: $justification', style: TextStyle(fontSize: 11, color: Colors.amber[800])),
          ],
          if (overriddenBy != null) ...[
            const SizedBox(height: 4),
            Text('Overridden by: $overriddenBy', style: const TextStyle(fontSize: 11, color: Colors.red)),
          ],
        ],
      ),
    );
  }

  // NEW: label + tap-to-reveal "?" info tooltip. Uses Flutter's own
  // built-in Tooltip widget rather than a custom overlay — this app
  // already relies on Tooltip elsewhere (NotificationBell's icon uses
  // the `tooltip:` shorthand), so this keeps the same mechanism instead
  // of introducing a second, different way of showing help text.
  // triggerMode: tap makes it show on a single tap on mobile (the
  // default is a long-press, which is far less discoverable) and still
  // shows on hover for desktop/web builds.
  Widget _fieldLabel(String text, String tooltip, Color subTextColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: subTextColor, letterSpacing: 0.3),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: tooltip,
          triggerMode: TooltipTriggerMode.tap,
          showDuration: const Duration(seconds: 5),
          decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, height: 1.4),
          padding: const EdgeInsets.all(10),
          child: Container(
            width: 14,
            height: 14,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.35), shape: BoxShape.circle),
            child: const Text('?', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFFF59E0B), letterSpacing: 0.8),
      ),
    );
  }

  Widget _buildConfigSection(bool isDark, Color cardColor, Color borderColor, Color textColor, Color subTextColor) {
    if (_isLoadingThresholds) return const Center(child: CircularProgressIndicator());

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, style: BorderStyle.solid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Detection Settings',
                    style: GoogleFonts.cormorantGaramond(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('LIVE SYNCED',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.green[700], letterSpacing: 0.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Changes apply immediately to every branch and every open device — web included. Tap a ? for its definition.',
              style: TextStyle(fontSize: 11, color: subTextColor)),
          const SizedBox(height: 20),

          _sectionTitle('SALE VALUE'),
          _buildThresholdRow([
            _numField('Elevated Sale Threshold', 'avgMultiplier',
                'The size of a transaction, expressed as a multiple of this branch\'s typical sale, at which a sale is considered elevated.',
                textColor, subTextColor, borderColor, isDark),
            _numField('Severe Sale Threshold', 'criticalMultiplier',
                'The size of a transaction, expressed as a multiple of this branch\'s typical sale, at which a sale is considered severely elevated.',
                textColor, subTextColor, borderColor, isDark),
            _numField('Minimum Sales for Baseline', 'minBaselineTransactions',
                'The number of prior walk-in sales at a branch required to establish a reliable typical-sale amount.',
                textColor, subTextColor, borderColor, isDark),
          ]),
          const SizedBox(height: 16),
          _buildThresholdRow([
            _numField('Fallback Value Threshold (₱)', 'fallbackHighValueThreshold',
                'A fixed peso amount used to judge whether a sale is elevated when a branch does not yet have enough sales history to establish a baseline.',
                textColor, subTextColor, borderColor, isDark),
            _numField('Peak Season Elevated Threshold', 'peakAvgMultiplier',
                'The Elevated Sale Threshold used specifically during the Peak Season Dates configured below.',
                textColor, subTextColor, borderColor, isDark),
            _numField('Peak Season Severe Threshold', 'peakCriticalMultiplier',
                'The Severe Sale Threshold used specifically during the Peak Season Dates configured below.',
                textColor, subTextColor, borderColor, isDark),
          ]),
          const SizedBox(height: 16),
          _peakDatesField(textColor, subTextColor, borderColor, isDark),

          const SizedBox(height: 20),
          _sectionTitle('VOIDS & REFUNDS'),
          _buildThresholdRow([
            _numField('Void Review Window (hours)', 'voidWindowHours',
                'The rolling time period over which a staff member\'s voids and refunds are counted.',
                textColor, subTextColor, borderColor, isDark),
            _numField('Elevated Void Count', 'voidCountMedium',
                'The number of voids or refunds by one staff member within the Void Review Window considered elevated.',
                textColor, subTextColor, borderColor, isDark),
            _numField('Severe Void Count', 'voidCountCritical',
                'The number of voids or refunds by one staff member within the Void Review Window considered severe.',
                textColor, subTextColor, borderColor, isDark),
          ]),

          const SizedBox(height: 20),
          _sectionTitle('DISCOUNTS'),
          _buildThresholdRow([
            _numField('Elevated Discount Percentage', 'discountMediumPercent',
                'The manual discount percentage on a single transaction considered elevated.',
                textColor, subTextColor, borderColor, isDark),
            _numField('Severe Discount Percentage', 'discountCriticalPercent',
                'The manual discount percentage on a single transaction considered severe.',
                textColor, subTextColor, borderColor, isDark),
          ]),

          const SizedBox(height: 20),
          _sectionTitle('STORE HOURS'),
          Row(
            children: [
              Expanded(
                child: _timeField('Store Opening Time', _to12HourDisplay(_storeOpenTime24), () => _pickTime(true),
                    'The time of day this branch normally opens for business.',
                    textColor, subTextColor, borderColor, isDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _timeField('Store Closing Time', _to12HourDisplay(_storeCloseTime24), () => _pickTime(false),
                    'The time of day this branch normally closes for business.',
                    textColor, subTextColor, borderColor, isDark),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('SAVE SETTINGS',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThresholdRow(List<Widget> children) {
    return Row(
      children: children
          .map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0), child: c)))
          .toList(),
    );
  }

  Widget _numField(String label, String key, String tooltip, Color textColor, Color subTextColor, Color borderColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, tooltip, subTextColor),
        const SizedBox(height: 6),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF222222) : const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: _controllers[key],
            focusNode: _focusNodes[key],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }

  // NEW: multi-line "one range per line" field for peakDates, matching
  // the web dashboard's textarea exactly — same "YYYY-MM-DD to
  // YYYY-MM-DD" line format, same parse/serialize round trip.
  Widget _peakDatesField(Color textColor, Color subTextColor, Color borderColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(
          'Peak Season Dates (one range per line)',
          'Date ranges during which higher sales volume is expected and normal, such as known holidays or seasonal events.',
          subTextColor,
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF222222) : const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: TextField(
            controller: _peakDatesController,
            focusNode: _peakDatesFocus,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: '2026-02-10 to 2026-02-15\n2026-05-04 to 2026-05-11',
              hintStyle: TextStyle(fontSize: 12, color: subTextColor.withValues(alpha: 0.6)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _timeField(String label, String value, VoidCallback onTap, String tooltip, Color textColor, Color subTextColor, Color borderColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, tooltip, subTextColor),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF222222) : const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor)),
                Icon(Icons.access_time, size: 16, color: subTextColor),
              ],
            ),
          ),
        ),
      ],
    );
  }
}