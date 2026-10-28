import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'delivery_schedule.dart';

/// The inside of the "Delivery Date & Time" card on the checkout screen.
/// (The page wraps it in its own `_sectionCard`, so the card frame matches the
/// other sections.) It owns no state: the page keeps the choice and this widget
/// just draws it and reports taps through the callbacks.
class DeliveryScheduleSection extends StatelessWidget {
  final bool isScheduled;
  final DateTime? date;
  final DeliverySlot? slot;
  final ValueChanged<bool> onModeChanged; // true = "Pick a date & time"
  final VoidCallback onPickDate;
  final ValueChanged<DeliverySlot> onSlotSelected;

  const DeliveryScheduleSection({
    super.key,
    required this.isScheduled,
    required this.date,
    required this.slot,
    required this.onModeChanged,
    required this.onPickDate,
    required this.onSlotSelected,
  });

  static const Color _accent = Color(0xFFF4B400);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final fieldColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F8F6);

    // "Manila now" is read once per redraw so every chip below agrees with the others.
    final now = DeliveryScheduleRules.manilaNow();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _modeButton(
                label: 'As soon as possible',
                icon: Icons.bolt_outlined,
                selected: !isScheduled,
                onTap: () => onModeChanged(false),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _modeButton(
                label: 'Pick date & time',
                icon: Icons.event_outlined,
                selected: isScheduled,
                onTap: () => onModeChanged(true),
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          isScheduled
              ? 'Choose a day and a 2-hour window. Florists need at least '
              '${DeliveryScheduleRules.leadMinutes ~/ 60} hours to prepare, and you can book up to '
              '${DeliveryScheduleRules.maxDaysAhead} days ahead (Philippine time).'
              : 'We will prepare and deliver your flowers as soon as we can.',
          style: TextStyle(fontSize: 11, height: 1.4, color: subColor),
        ),

        if (isScheduled) ...[
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
              decoration: BoxDecoration(color: fieldColor, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined, color: _accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      date == null ? 'Select delivery date' : DateFormat('EEEE, MMM d, yyyy').format(date!),
                      style: TextStyle(
                        fontSize: 14,
                        color: date == null ? subColor : textColor,
                        fontWeight: date == null ? FontWeight.normal : FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down, color: subColor),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (date == null)
            Text('Pick a date to see the available time windows.',
                style: TextStyle(fontSize: 11, color: subColor))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DeliveryScheduleRules.slots.map((s) {
                final available = DeliveryScheduleRules.isSlotAvailable(date!, s, now: now);
                final selected = slot?.value == s.value && available;
                return ChoiceChip(
                  label: Text(s.label),
                  selected: selected,
                  // null = greyed out and untappable (that window is too soon).
                  onSelected: available ? (_) => onSlotSelected(s) : null,
                  selectedColor: _accent,
                  backgroundColor: fieldColor,
                  disabledColor: isDark ? const Color(0xFF222222) : const Color(0xFFEDEDED),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? const Color(0xFF121212)
                        : (available ? textColor : subColor.withOpacity(0.5)),
                    decoration: available ? null : TextDecoration.lineThrough,
                  ),
                  side: BorderSide(color: selected ? _accent : Colors.transparent),
                );
              }).toList(),
            ),
        ],
      ],
    );
  }

  Widget _modeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? _accent.withOpacity(isDark ? 0.18 : 0.14)
              : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F8F6)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? _accent : Colors.transparent, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? _accent : Colors.grey),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: selected ? _accent : (isDark ? Colors.grey[300] : Colors.grey[700]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
