import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'inventory_data.dart';

class NotificationBell extends StatelessWidget {
  final Color iconColor;
  const NotificationBell({super.key, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: InventoryData.notificationsStream(),
      builder: (context, snapshot) {
        final notifications = snapshot.data ?? [];
        final unreadCount = notifications.where((n) => n['read'] != true).length;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(Icons.notifications_none_rounded, color: iconColor, size: 20),
              tooltip: 'Notifications',
              onPressed: () => openNotificationsSheet(context),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Color _typeColor(String type) {
  switch (type) {
    case 'success':
      return Colors.green;
    case 'warning':
      return Colors.orange;
    case 'error':
      return Colors.red;
    default:
      return const Color(0xFFF59E0B);
  }
}

// NEW: pulled out of NotificationBell so ANY tappable element — the bell
// icon here, or a plain settings-style row like Profile's "Notifications"
// tile — can open the exact same panel. This function owns its own
// StreamBuilder, so callers never need to fetch or pass in a notification
// list themselves; they just call this one function with a BuildContext.
void openNotificationsSheet(BuildContext context) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
  final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
  final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
  final borderColor = isDark ? const Color(0xFF2A2A2A) : Colors.grey.withValues(alpha: 0.15);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: InventoryData.notificationsStream(),
            builder: (context, snapshot) {
              final notifications = snapshot.data ?? [];
              return Container(
                decoration: BoxDecoration(color: cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
                          if (notifications.any((n) => n['read'] != true))
                            TextButton(
                              onPressed: () => InventoryData.markAllNotificationsRead(notifications.map((n) => n['id'] as String).toList()),
                              child: const Text('Mark all read', style: TextStyle(fontSize: 12, color: Color(0xFFF59E0B))),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: notifications.isEmpty
                          ? Center(child: Text('No notifications yet.', style: TextStyle(color: subTextColor)))
                          : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final n = notifications[index];
                          final isRead = n['read'] == true;
                          final color = _typeColor((n['type'] ?? 'info').toString());
                          final ts = n['created_at'];
                          final timeStr = ts is Timestamp ? DateFormat('MMM d, h:mm a').format(ts.toDate()) : '';

                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              if (!isRead) InventoryData.markNotificationRead(n['id']);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isRead ? Colors.transparent : color.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: borderColor),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(color: isRead ? Colors.transparent : color, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(n['title'] ?? 'Notification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor)),
                                        const SizedBox(height: 3),
                                        Text(n['message'] ?? '', style: TextStyle(fontSize: 12, color: subTextColor)),
                                        const SizedBox(height: 4),
                                        Text(timeStr, style: TextStyle(fontSize: 10, color: subTextColor.withValues(alpha: 0.7))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}