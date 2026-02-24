import '../domain/item_enums.dart';
import '../domain/return_item.dart';
import 'items_repository.dart';

class MockItemsRepository implements ItemsRepository {
  MockItemsRepository();

  @override
  Stream<List<ReturnItem>> watchItems({required String uid}) {
    return Stream.value(_seedItems(uid: uid));
  }

  @override
  Future<void> createManualItem({
    required String uid,
    required String title,
    required StoreType store,
    required ItemStatus status,
    required DateTime deliveredAt,
    required DateTime returnDeadline,
    String? notes,
  }) async {}

  @override
  Future<void> updateItem(ReturnItem item) async {}

  @override
  Future<void> deleteItem({
    required String uid,
    required String itemId,
  }) async {}

  List<ReturnItem> _seedItems({required String uid}) {
    final now = DateTime.now();

    ReturnItem buildItem({
      required String id,
      required String title,
      required StoreType store,
      required ItemStatus status,
      required int deliveredDaysAgo,
      required int deadlineInDays,
      required int returnWindowDays,
      String? orderId,
      ItemSource source = ItemSource.manual,
    }) {
      final deliveredAt = now.subtract(Duration(days: deliveredDaysAgo));
      final returnDeadline = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: deadlineInDays));

      return ReturnItem(
        id: id,
        uid: uid,
        title: title,
        store: store,
        status: status,
        deliveredAt: deliveredAt,
        returnDeadline: returnDeadline,
        returnWindowDays: returnWindowDays,
        createdAt: deliveredAt,
        updatedAt: now,
        orderId: orderId,
        normalizedTitle: title.toLowerCase(),
        source: source,
      );
    }

    return [
      buildItem(
        id: 'item_1',
        title: 'Noise Cancelling Headphones',
        store: StoreType.amazon,
        status: ItemStatus.pending,
        deliveredDaysAgo: 3,
        deadlineInDays: 27,
        returnWindowDays: 30,
        orderId: 'AMZ-341221',
      ),
      buildItem(
        id: 'item_2',
        title: 'Travel Backpack',
        store: StoreType.other,
        status: ItemStatus.pending,
        deliveredDaysAgo: 12,
        deadlineInDays: 4,
        returnWindowDays: 30,
      ),
      buildItem(
        id: 'item_3',
        title: 'Winter Jacket',
        store: StoreType.shein,
        status: ItemStatus.keep,
        deliveredDaysAgo: 18,
        deadlineInDays: 12,
        returnWindowDays: 35,
        source: ItemSource.gmailSync,
      ),
      buildItem(
        id: 'item_4',
        title: 'Kitchen Scale',
        store: StoreType.amazon,
        status: ItemStatus.returnItem,
        deliveredDaysAgo: 16,
        deadlineInDays: 9,
        returnWindowDays: 30,
      ),
      buildItem(
        id: 'item_5',
        title: 'Running Shoes',
        store: StoreType.other,
        status: ItemStatus.expired,
        deliveredDaysAgo: 42,
        deadlineInDays: -8,
        returnWindowDays: 30,
      ),
      buildItem(
        id: 'item_6',
        title: 'Desk Lamp',
        store: StoreType.amazon,
        status: ItemStatus.pending,
        deliveredDaysAgo: 33,
        deadlineInDays: -2,
        returnWindowDays: 30,
      ),
    ];
  }
}
