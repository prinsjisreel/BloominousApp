import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class SalesAnomaliesPage extends StatefulWidget {
  const SalesAnomaliesPage({super.key});

  @override
  State<SalesAnomaliesPage> createState() => _SalesAnomaliesPageState();
}

class _SalesAnomaliesPageState extends State<SalesAnomaliesPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _selectedSeverityFilter = 'ALL'; // 'ALL', 'CRITICAL', 'MEDIUM', 'LOW'

  // Threshold Controllers
  final TextEditingController _valueSpikeMediumCtrl =
      TextEditingController(text: '5');
  final TextEditingController _valueSpikeCriticalCtrl =
      TextEditingController(text: '10');
  final TextEditingController _minTxBaselineCtrl =
      TextEditingController(text: '5');
  final TextEditingController _fallbackFlatCtrl =
      TextEditingController(text: '5000');
  final TextEditingController _voidWindowCtrl =
      TextEditingController(text: '24');
  final TextEditingController _voidCountMediumCtrl =
      TextEditingController(text: '2');
  final TextEditingController _voidCountCriticalCtrl =
      TextEditingController(text: '4');
  final TextEditingController _discountMediumCtrl =
      TextEditingController(text: '15');
  final TextEditingController _discountCriticalCtrl =
      TextEditingController(text: '30');
  final TextEditingController _openingTimeCtrl =
      TextEditingController(text: '08:00 AM');
  final TextEditingController _closingTimeCtrl =
      TextEditingController(text: '08:00 PM');

  bool _isSavingThresholds = false;
  bool _isLoadingThresholds = true;

  @override
  void initState() {
    super.initState();
    _loadThresholds();
  }

  Future<void> _loadThresholds() async {
    try {
      final doc = await _db
          .collection('settings')
          .doc('salesAnomaliesThresholds')
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _valueSpikeMediumCtrl.text = (data['valueSpikeMedium'] ?? 5).toString();
        _valueSpikeCriticalCtrl.text =
            (data['valueSpikeCritical'] ?? 10).toString();
        _minTxBaselineCtrl.text = (data['minTxBaseline'] ?? 5).toString();
        _fallbackFlatCtrl.text =
            (data['fallbackFlatThreshold'] ?? 5000).toString();
        _voidWindowCtrl.text = (data['voidWindowHours'] ?? 24).toString();
        _voidCountMediumCtrl.text = (data['voidCountMedium'] ?? 2).toString();
        _voidCountCriticalCtrl.text =
            (data['voidCountCritical'] ?? 4).toString();
        _discountMediumCtrl.text =
            (data['discountMediumPercent'] ?? 15).toString();
        _discountCriticalCtrl.text =
            (data['discountCriticalPercent'] ?? 30).toString();
        _openingTimeCtrl.text = data['storeOpeningTime'] ?? '08:00 AM';
        _closingTimeCtrl.text = data['storeClosingTime'] ?? '08:00 PM';
      }
    } catch (e) {
      debugPrint('Error loading thresholds: $e');
    } finally {
      if (mounted) setState(() => _isLoadingThresholds = false);
    }
  }

  Future<void> _saveThresholds() async {
    setState(() => _isSavingThresholds = true);
    try {
      await _db.collection('settings').doc('salesAnomaliesThresholds').set({
        'valueSpikeMedium': double.tryParse(_valueSpikeMediumCtrl.text) ?? 5.0,
        'valueSpikeCritical':
            double.tryParse(_valueSpikeCriticalCtrl.text) ?? 10.0,
        'minTxBaseline': int.tryParse(_minTxBaselineCtrl.text) ?? 5,
        'fallbackFlatThreshold':
            double.tryParse(_fallbackFlatCtrl.text) ?? 5000.0,
        'voidWindowHours': int.tryParse(_voidWindowCtrl.text) ?? 24,
        'voidCountMedium': int.tryParse(_voidCountMediumCtrl.text) ?? 2,
        'voidCountCritical': int.tryParse(_voidCountCriticalCtrl.text) ?? 4,
        'discountMediumPercent':
            double.tryParse(_discountMediumCtrl.text) ?? 15.0,
        'discountCriticalPercent':
            double.tryParse(_discountCriticalCtrl.text) ?? 30.0,
        'storeOpeningTime': _openingTimeCtrl.text,
        'storeClosingTime': _closingTimeCtrl.text,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Thresholds saved successfully! Applied across all branch nodes.'),
            backgroundColor: Color(0xFFF59E0B),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving thresholds: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingThresholds = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFFFFDF9),
      appBar: AppBar(
        title: Text(
          'Sales Anomalies Detection',
          style: GoogleFonts.cormorantGaramond(
              fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: isDark ? Colors.black : const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('sales_anomalies').snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];

          int totalFlagged = docs.length;
          int criticalCount = docs
              .where((d) =>
                  (d.data() as Map<String, dynamic>)['severity'] == 'CRITICAL')
              .length;
          int mediumCount = docs
              .where((d) =>
                  (d.data() as Map<String, dynamic>)['severity'] == 'MEDIUM')
              .length;
          int lowCount = docs
              .where((d) =>
                  (d.data() as Map<String, dynamic>)['severity'] == 'LOW')
              .length;

          final filteredDocs = docs.where((doc) {
            if (_selectedSeverityFilter == 'ALL') return true;
            final data = doc.data() as Map<String, dynamic>;
            return data['severity'] == _selectedSeverityFilter;
          }).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Page Description Subtitle
                Text(
                  'Internal transactional irregularity monitoring — value spikes, void frequency, excessive discounts, off-hours activity.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 20),

                // Metrics Row
                Row(
                  children: [
                    _buildMetricCard('TOTAL FLAGGED', '$totalFlagged',
                        Colors.black87, isDark),
                    const SizedBox(width: 12),
                    _buildMetricCard(
                        'CRITICAL', '$criticalCount', Colors.redAccent, isDark),
                    const SizedBox(width: 12),
                    _buildMetricCard(
                        'MEDIUM', '$mediumCount', Colors.orange, isDark),
                    const SizedBox(width: 12),
                    _buildMetricCard('LOW', '$lowCount', Colors.green, isDark),
                  ],
                ),
                const SizedBox(height: 20),

                // Severity Filter Buttons
                Row(
                  children: [
                    _buildFilterChip('ALL', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('CRITICAL', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('MEDIUM', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('LOW', isDark),
                  ],
                ),
                const SizedBox(height: 24),

                // Anomalies List or Empty State
                if (filteredDocs.isEmpty)
                  Container(
                    height: 180,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[900] : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withOpacity(0.15)),
                    ),
                    child: Text(
                      'No anomalies in this view.',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final data =
                          filteredDocs[index].data() as Map<String, dynamic>;
                      final severity = data['severity'] ?? 'MEDIUM';
                      final title = data['type'] ??
                          data['title'] ??
                          'Irregular Transaction Flagged';
                      final description = data['description'] ??
                          'Suspicious pattern identified.';
                      final branch = data['branch'] ?? 'Main Branch';
                      final staff = data['staffName'] ?? 'Staff';
                      final timestamp = data['createdAt'] != null
                          ? (data['createdAt'] as Timestamp).toDate()
                          : DateTime.now();

                      Color sevColor = severity == 'CRITICAL'
                          ? Colors.red
                          : (severity == 'MEDIUM'
                              ? Colors.orange
                              : Colors.green);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: sevColor.withOpacity(0.3)),
                        ),
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: sevColor.withOpacity(0.1),
                                child: Icon(Icons.warning_amber_rounded,
                                    color: sevColor),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: sevColor.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            severity,
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: sevColor),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(description,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[700])),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Branch: $branch • Staff: $staff • ${DateFormat('MMM dd, hh:mm a').format(timestamp)}',
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 32),

                // Detection Thresholds Form Card (Screenshot 3)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detection Thresholds',
                        style: GoogleFonts.cormorantGaramond(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Changes apply immediately to every branch — no redeploy needed.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 24),
                      if (_isLoadingThresholds)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        // Row 1
                        _buildThresholdRow([
                          _buildField('VALUE SPIKE — MEDIUM MULTIPLIER (X AVG)',
                              _valueSpikeMediumCtrl),
                          _buildField(
                              'VALUE SPIKE — CRITICAL MULTIPLIER (X AVG)',
                              _valueSpikeCriticalCtrl),
                          _buildField('MIN. TRANSACTIONS FOR BASELINE',
                              _minTxBaselineCtrl),
                        ]),
                        const SizedBox(height: 16),

                        // Row 2
                        _buildThresholdRow([
                          _buildField(
                              'FALLBACK FLAT THRESHOLD (P)', _fallbackFlatCtrl),
                          _buildField('VOID WINDOW (HOURS)', _voidWindowCtrl),
                          _buildField(
                              'VOID COUNT — MEDIUM', _voidCountMediumCtrl),
                        ]),
                        const SizedBox(height: 16),

                        // Row 3
                        _buildThresholdRow([
                          _buildField(
                              'VOID COUNT — CRITICAL', _voidCountCriticalCtrl),
                          _buildField(
                              'DISCOUNT % — MEDIUM', _discountMediumCtrl),
                          _buildField(
                              'DISCOUNT % — CRITICAL', _discountCriticalCtrl),
                        ]),
                        const SizedBox(height: 16),

                        // Row 4 & Button
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                                child: _buildTimePickerField(
                                    'STORE OPENING TIME', _openingTimeCtrl)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _buildTimePickerField(
                                    'STORE CLOSING TIME', _closingTimeCtrl)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _isSavingThresholds
                                      ? null
                                      : _saveThresholds,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF59E0B),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    elevation: 0,
                                  ),
                                  child: _isSavingThresholds
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2))
                                      : const Text(
                                          'SAVE THRESHOLDS',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              letterSpacing: 0.5),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricCard(
      String label, String value, Color textColor, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.grey[500],
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: textColor == Colors.black87 && isDark
                    ? Colors.white
                    : textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isDark) {
    final bool isSelected = _selectedSeverityFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedSeverityFilter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF0F172A)
              : (isDark ? Colors.grey[800] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.grey[300] : Colors.grey[700]),
          ),
        ),
      ),
    );
  }

  Widget _buildThresholdRow(List<Widget> children) {
    return Row(
      children: children
          .map((c) => Expanded(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: c)))
          .toList(),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 0.3),
        ),
        const SizedBox(height: 6),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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

  Widget _buildTimePickerField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 0.3),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final TimeOfDay? picked = await showTimePicker(
              context: context,
              initialTime: const TimeOfDay(hour: 8, minute: 0),
            );
            if (picked != null) {
              final now = DateTime.now();
              final dt = DateTime(
                  now.year, now.month, now.day, picked.hour, picked.minute);
              ctrl.text = DateFormat('hh:mm a').format(dt);
            }
          },
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  ctrl.text,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const Icon(Icons.access_time, size: 16, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
