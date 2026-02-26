import '../domain/item_enums.dart';
import '../domain/return_item.dart';

abstract class ItemsRepository {
  Stream<List<ReturnItem>> watchItems({required String uid});

  Future<void> createManualItem({
    required String uid,
    required String title,
    required StoreType store,
    required ItemStatus status,
    required DateTime deliveredAt,
    required DateTime returnDeadline,
    String? notes,
  });

  Future<void> updateItem(ReturnItem item);

  Future<void> deleteItem({required String uid, required String itemId});

  Future<int> expireOverduePendingItems({required String uid});
}
