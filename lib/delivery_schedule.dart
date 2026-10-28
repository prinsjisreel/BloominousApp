import 'package:intl/intl.dart';

/// One 2-hour delivery window.
///
/// SHARED WEB + APP CONTRACT: these five windows, their `value` strings, the
/// 3-hour lead time and the 30-day limit are identical to DELIVERY_SLOTS in
/// templates/checkout.php and BLOOM_DELIVERY_SLOTS in submit_order.php.
/// `value` is what travels to the server; `label` is only for the screen.
class DeliverySlot {
  final String value; // e.g. '08:00-10:00' (the server matches on this exact text)
  final String label; // e.g. '8:00 AM – 10:00 AM'
  final int startHour; // 24-hour clock, Manila time
  final int endHour;

  const DeliverySlot({
    required this.value,
    required this.label,
    required this.startHour,
    required this.endHour,
  });
}

/// What the customer picked: "as soon as possible" or a date + time window.
class DeliverySchedule {
  final bool isAsap;
  final DateTime? date; // only year / month / day matter (Manila calendar day)
  final DeliverySlot? slot;

  const DeliverySchedule.asap()
      : isAsap = true,
        date = null,
        slot = null;

  const DeliverySchedule.scheduled({this.date, this.slot}) : isAsap = false;

  /// The exact JSON object submit_order.php reads as `deliverySchedule`.
  /// ASAP sends only the mode; the server fills the six order fields with nulls.
  Map<String, dynamic> toPayload() {
    if (isAsap || date == null || slot == null) {
      return {'mode': 'asap'};
    }
    return {
      'mode': 'scheduled',
      'date': DateFormat('yyyy-MM-dd').format(date!),
      'slot': slot!.value,
    };
  }

  /// Short text for the order summary on screen.
  String get summary {
    if (isAsap || date == null || slot == null) return 'As soon as possible';
    return '${DateFormat('EEE, MMM d, yyyy').format(date!)} · ${slot!.label}';
  }
}

/// All the scheduling rules in one place, so the checkout screen only asks
/// questions ("is this slot allowed?") and never does date math itself.
///
/// TIME ZONE NOTE: the shop works in Asia/Manila, which is always UTC+8 (the
/// Philippines has no daylight saving). So "Manila now" is simply the current
/// UTC time plus 8 hours. The result is stored in a UTC-flagged DateTime purely
/// as a container: its year/month/day/hour fields ARE the Manila wall clock,
/// whatever time zone the phone itself is set to.
class DeliveryScheduleRules {
  static const int leadMinutes = 180; // florists need 3 hours to prepare
  static const int maxDaysAhead = 30;

  static const List<DeliverySlot> slots = [
    DeliverySlot(value: '08:00-10:00', label: '8:00 AM – 10:00 AM', startHour: 8, endHour: 10),
    DeliverySlot(value: '10:00-12:00', label: '10:00 AM – 12:00 PM', startHour: 10, endHour: 12),
    DeliverySlot(value: '12:00-14:00', label: '12:00 PM – 2:00 PM', startHour: 12, endHour: 14),
    DeliverySlot(value: '14:00-16:00', label: '2:00 PM – 4:00 PM', startHour: 14, endHour: 16),
    DeliverySlot(value: '16:00-18:00', label: '4:00 PM – 6:00 PM', startHour: 16, endHour: 18),
  ];

  /// The current wall-clock time in Manila (see the note above the class).
  static DateTime manilaNow() => DateTime.now().toUtc().add(const Duration(hours: 8));

  /// Strips any time-of-day and time-zone baggage: only the calendar day remains.
  static DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// When a given slot on a given day begins, in the same "Manila wall clock" form.
  static DateTime _slotStart(DateTime date, DeliverySlot slot) =>
      DateTime.utc(date.year, date.month, date.day, slot.startHour);

  /// The very last moment a delivery may still be booked for
  /// (end of today + 30 days) — same formula as submit_order.php.
  static DateTime _lastAllowedMoment(DateTime now) =>
      DateTime.utc(now.year, now.month, now.day, 23, 59, 59).add(const Duration(days: maxDaysAhead));

  /// True when [slot] on [date] starts at least 3 hours from now and is not
  /// beyond the 30-day window.
  static bool isSlotAvailable(DateTime date, DeliverySlot slot, {DateTime? now}) {
    final current = now ?? manilaNow();
    final start = _slotStart(date, slot);
    if (start.isBefore(current.add(const Duration(minutes: leadMinutes)))) return false;
    if (start.isAfter(_lastAllowedMoment(current))) return false;
    return true;
  }

  /// True when at least one of the five windows on [date] can still be booked.
  static bool isDateSelectable(DateTime date, {DateTime? now}) {
    final current = now ?? manilaNow();
    return slots.any((s) => isSlotAvailable(date, s, now: current));
  }

  /// The first day that still has a bookable window (usually today or tomorrow).
  static DateTime? earliestSelectableDate({DateTime? now}) {
    final current = now ?? manilaNow();
    final today = dateOnly(current);
    for (int i = 0; i <= maxDaysAhead; i++) {
      final candidate = today.add(Duration(days: i));
      if (isDateSelectable(candidate, now: current)) return candidate;
    }
    return null;
  }

  /// The last calendar day the customer may pick.
  static DateTime lastSelectableDate({DateTime? now}) {
    final current = now ?? manilaNow();
    return dateOnly(current).add(const Duration(days: maxDaysAhead));
  }

  /// Returns a friendly error message, or null when the choice is fine.
  /// Runs before ordering (so the customer gets instant feedback) — the server
  /// repeats the very same checks, so a tampered app cannot skip them.
  static String? validate(DeliverySchedule schedule, {DateTime? now}) {
    if (schedule.isAsap) return null;
    if (schedule.date == null) return 'Please choose a delivery date.';
    if (schedule.slot == null) return 'Please choose a delivery time window.';

    final current = now ?? manilaNow();
    final start = _slotStart(schedule.date!, schedule.slot!);

    if (start.isBefore(current.add(const Duration(minutes: leadMinutes)))) {
      return 'That delivery time is too soon. Our florists need at least '
          '${leadMinutes ~/ 60} hours to prepare your order. Please choose a later time.';
    }
    if (start.isAfter(_lastAllowedMoment(current))) {
      return 'Deliveries can be scheduled up to $maxDaysAhead days ahead. Please choose an earlier date.';
    }
    return null;
  }
}
