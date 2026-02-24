import 'package:cloud_firestore/cloud_firestore.dart';

import '../../contracts/firestore_contract.dart' as contract;
import '../domain/item_enums.dart';
import '../domain/return_item.dart';
import 'items_repository.dart';

class FirestoreItemsRepository implements ItemsRepository {
  FirestoreItemsRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _itemsCollection({
    required String uid,
  }) {
    return _firestore
        .collection(contract.FirestoreContract.users)
        .doc(uid)
        .collection(contract.UserSubcollections.items);
  }

  @override
  Stream<List<ReturnItem>> watchItems({required String uid}) {
    return _itemsCollection(
      uid: uid,
    ).orderBy(contract.ItemFields.returnDeadline).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => _itemFromDocument(uid: uid, doc: doc))
          .toList();
    });
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
  }) async {
    final now = DateTime.now();
    final docRef = _itemsCollection(uid: uid).doc();

    final item = ReturnItem(
      id: docRef.id,
      uid: uid,
      title: title.trim(),
      store: store,
      status: status,
      deliveredAt: deliveredAt,
      returnDeadline: returnDeadline,
      returnWindowDays: _returnWindowDays(
        deliveredAt: deliveredAt,
        returnDeadline: returnDeadline,
      ),
      createdAt: now,
      updatedAt: now,
      normalizedTitle: title.trim().toLowerCase(),
      source: ItemSource.manual,
      messageIds: const [],
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
    );

    await docRef.set(_toFirestore(item));
  }

  @override
  Future<void> updateItem(ReturnItem item) async {
    await _itemsCollection(uid: item.uid).doc(item.id).set(_toFirestore(item));
  }

  @override
  Future<void> deleteItem({required String uid, required String itemId}) async {
    await _itemsCollection(uid: uid).doc(itemId).delete();
  }

  int _returnWindowDays({
    required DateTime deliveredAt,
    required DateTime returnDeadline,
  }) {
    final deliveredDate = DateTime(
      deliveredAt.year,
      deliveredAt.month,
      deliveredAt.day,
    );
    final deadlineDate = DateTime(
      returnDeadline.year,
      returnDeadline.month,
      returnDeadline.day,
    );
    final days = deadlineDate.difference(deliveredDate).inDays + 1;
    if (days < 1) {
      return 1;
    }
    if (days > 120) {
      return 120;
    }
    return days;
  }

  ReturnItem _itemFromDocument({
    required String uid,
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  }) {
    final data = doc.data();
    return ReturnItem(
      id: doc.id,
      uid: data[contract.ItemFields.uid] as String? ?? uid,
      title: data[contract.ItemFields.title] as String? ?? '',
      store: _storeFromString(data[contract.ItemFields.store] as String?),
      status: _statusFromString(data[contract.ItemFields.status] as String?),
      deliveredAt: _timestampToDate(data[contract.ItemFields.deliveredAt]),
      returnDeadline: _timestampToDate(
        data[contract.ItemFields.returnDeadline],
      ),
      returnWindowDays:
          (data[contract.ItemFields.returnWindowDays] as int?) ?? 30,
      createdAt: _timestampToDate(data[contract.ItemFields.createdAt]),
      updatedAt: _timestampToDate(data[contract.ItemFields.updatedAt]),
      orderId: data[contract.ItemFields.orderId] as String?,
      normalizedTitle: data[contract.ItemFields.normalizedTitle] as String?,
      source: _sourceFromString(data[contract.ItemFields.source] as String?),
      messageIds:
          (data[contract.ItemFields.messageIds] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(),
      notes: data[contract.ItemFields.notes] as String?,
    );
  }

  DateTime _timestampToDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return DateTime.now();
  }

  Map<String, dynamic> _toFirestore(ReturnItem item) {
    final data = <String, dynamic>{
      contract.ItemFields.uid: item.uid,
      contract.ItemFields.title: item.title.trim(),
      contract.ItemFields.store: _storeToString(item.store),
      contract.ItemFields.status: _statusToString(item.status),
      contract.ItemFields.deliveredAt: Timestamp.fromDate(item.deliveredAt),
      contract.ItemFields.returnDeadline: Timestamp.fromDate(
        item.returnDeadline,
      ),
      contract.ItemFields.returnWindowDays: item.returnWindowDays,
      contract.ItemFields.createdAt: Timestamp.fromDate(item.createdAt),
      contract.ItemFields.updatedAt: Timestamp.fromDate(item.updatedAt),
      contract.ItemFields.normalizedTitle:
          item.normalizedTitle ?? item.title.trim().toLowerCase(),
      contract.ItemFields.source: _sourceToString(item.source),
      contract.ItemFields.messageIds: item.messageIds,
    };

    if (item.orderId != null && item.orderId!.isNotEmpty) {
      data[contract.ItemFields.orderId] = item.orderId;
    }
    if (item.notes != null && item.notes!.isNotEmpty) {
      data[contract.ItemFields.notes] = item.notes;
    }

    return data;
  }

  String _statusToString(ItemStatus status) {
    return switch (status) {
      ItemStatus.pending => contract.ItemStatus.pending,
      ItemStatus.keep => contract.ItemStatus.keep,
      ItemStatus.returnItem => contract.ItemStatus.returnItem,
      ItemStatus.expired => contract.ItemStatus.expired,
    };
  }

  ItemStatus _statusFromString(String? value) {
    return switch (value) {
      contract.ItemStatus.keep => ItemStatus.keep,
      contract.ItemStatus.returnItem => ItemStatus.returnItem,
      contract.ItemStatus.expired => ItemStatus.expired,
      _ => ItemStatus.pending,
    };
  }

  String _sourceToString(ItemSource source) {
    return switch (source) {
      ItemSource.manual => contract.ItemSource.manual,
      ItemSource.gmailSync => contract.ItemSource.gmailSync,
    };
  }

  ItemSource _sourceFromString(String? value) {
    return switch (value) {
      contract.ItemSource.gmailSync => ItemSource.gmailSync,
      _ => ItemSource.manual,
    };
  }

  String _storeToString(StoreType store) {
    return switch (store) {
      StoreType.amazon => contract.StoreType.amazon,
      StoreType.shein => contract.StoreType.shein,
      StoreType.other => contract.StoreType.other,
    };
  }

  StoreType _storeFromString(String? value) {
    return switch (value) {
      contract.StoreType.amazon => StoreType.amazon,
      contract.StoreType.shein => StoreType.shein,
      _ => StoreType.other,
    };
  }
}
