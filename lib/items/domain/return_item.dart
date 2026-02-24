import 'item_enums.dart';

class ReturnItem {
  const ReturnItem({
    required this.id,
    required this.uid,
    required this.title,
    required this.store,
    required this.status,
    required this.deliveredAt,
    required this.returnDeadline,
    required this.returnWindowDays,
    required this.createdAt,
    required this.updatedAt,
    this.orderId,
    this.normalizedTitle,
    this.source = ItemSource.manual,
    this.messageIds = const [],
    this.notes,
  });

  final String id;
  final String uid;
  final String title;
  final StoreType store;
  final ItemStatus status;
  final DateTime deliveredAt;
  final DateTime returnDeadline;
  final int returnWindowDays;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? orderId;
  final String? normalizedTitle;
  final ItemSource source;
  final List<String> messageIds;
  final String? notes;

  bool get isInReturnPeriod =>
      status == ItemStatus.pending && daysRemaining >= 0;

  int get daysRemaining {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final deadlineDay = DateTime(
      returnDeadline.year,
      returnDeadline.month,
      returnDeadline.day,
    );
    return deadlineDay.difference(today).inDays;
  }
}
