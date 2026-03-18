import 'package:flutter/material.dart';
import '../main.dart'; // Inherit global colors

// --- MOCK DATA MODEL ---
class AppNotification {
  final String id;
  final String title;
  final String message;
  final String timeAgo;
  final bool isWarning;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.timeAgo,
    this.isWarning = false,
  });
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  // Mock Database of Notifications
  List<AppNotification> _notifications = [
    AppNotification(
      id: '1',
      title: 'PRA ALERT: Knee Valgus',
      message: 'High probability of patellofemoral injury detected. Knees collapsing inward during Squat phase. Recommend reducing weight and widening stance.',
      timeAgo: '2 hours ago',
      isWarning: true,
    ),
    AppNotification(
      id: '2',
      title: 'Workout Complete',
      message: 'Upper Body Power session logged successfully. Form score: 92%.',
      timeAgo: '1 day ago',
      isWarning: false,
    ),
    AppNotification(
      id: '3',
      title: 'PRA ALERT: Lumbar Flexion',
      message: 'Spinal rounding detected during deadlift setup. Continued execution may lead to disc herniation. Please review form tutorial.',
      timeAgo: '3 days ago',
      isWarning: true,
    ),
  ];

  void _removeNotification(String id) {
    setState(() {
      _notifications.removeWhere((n) => n.id == id);
    });
  }

  Widget _buildNotificationCard(AppNotification notification) {
    final borderColor = notification.isWarning ? neonRed : mintGreen;
    final iconColor = notification.isWarning ? neonRed : mintGreen;
    final icon = notification.isWarning ? Icons.warning_rounded : Icons.check_circle_outline;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: darkSlate,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withOpacity(0.8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    notification.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: notification.isWarning ? 0.5 : 0,
                    ),
                  ),
                ),
                Text(
                  notification.timeAgo,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              notification.message,
              style: const TextStyle(color: Colors.grey, height: 1.4),
            ),
            if (notification.isWarning) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: neonRed,
                    backgroundColor: neonRed.withOpacity(0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  onPressed: () => _removeNotification(notification.id),
                  child: const Text('ACKNOWLEDGE RISK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        centerTitle: false,
        actions: [
          if (_notifications.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _notifications.clear());
              },
              child: const Text('Clear All', style: TextStyle(color: mintGreen)),
            ),
        ],
      ),
      body: _notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off, size: 64, color: Colors.grey.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  const Text('No active alerts.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notification = _notifications[index];
                
                // Allow swipe-to-dismiss only for normal notifications
                if (!notification.isWarning) {
                  return Dismissible(
                    key: Key(notification.id),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => _removeNotification(notification.id),
                    background: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.red),
                    ),
                    child: _buildNotificationCard(notification),
                  );
                }
                
                // Warnings cannot be swiped; must tap Acknowledge
                return _buildNotificationCard(notification);
              },
            ),
    );
  }
}