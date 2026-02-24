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

  ReturnItem copyWith({
    String? id,
    String? uid,
    String? title,
    StoreType? store,
    ItemStatus? status,
    DateTime? deliveredAt,
    DateTime? returnDeadline,
    int? returnWindowDays,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? orderId,
    String? normalizedTitle,
    ItemSource? source,
    List<String>? messageIds,
    String? notes,
  }) {
    return ReturnItem(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      title: title ?? this.title,
      store: store ?? this.store,
      status: status ?? this.status,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      returnDeadline: returnDeadline ?? this.returnDeadline,
      returnWindowDays: returnWindowDays ?? this.returnWindowDays,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      orderId: orderId ?? this.orderId,
      normalizedTitle: normalizedTitle ?? this.normalizedTitle,
      source: source ?? this.source,
      messageIds: messageIds ?? this.messageIds,
      notes: notes ?? this.notes,
    );
  }

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
