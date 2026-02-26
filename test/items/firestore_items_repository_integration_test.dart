import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:returnsmanager/contracts/firestore_contract.dart' as contract;
import 'package:returnsmanager/items/data/firestore_items_repository.dart';
import 'package:returnsmanager/items/domain/item_enums.dart';
import 'package:returnsmanager/items/domain/return_item.dart';

void main() {
  group('FirestoreItemsRepository integration', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreItemsRepository repository;

    const uid = 'user_1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repository = FirestoreItemsRepository(firestore);
    });

    test(
      'expireOverduePendingItems expires only overdue pending items',
      () async {
        await repository.createManualItem(
          uid: uid,
          title: 'Overdue pending',
          store: StoreType.amazon,
          status: ItemStatus.pending,
          deliveredAt: DateTime(2026, 1, 1),
          returnDeadline: DateTime(2026, 1, 30),
        );
        await repository.createManualItem(
          uid: uid,
          title: 'Future pending',
          store: StoreType.other,
          status: ItemStatus.pending,
          deliveredAt: DateTime(2026, 2, 24),
          returnDeadline: DateTime(2026, 3, 25),
        );
        await repository.createManualItem(
          uid: uid,
          title: 'Keep item',
          store: StoreType.shein,
          status: ItemStatus.keep,
          deliveredAt: DateTime(2026, 2, 10),
          returnDeadline: DateTime(2026, 3, 15),
        );

        final expiredCount = await repository.expireOverduePendingItems(
          uid: uid,
        );
        expect(expiredCount, 1);

        final snapshot = await firestore
            .collection(contract.FirestoreContract.users)
            .doc(uid)
            .collection(contract.UserSubcollections.items)
            .get();
        final statusesByTitle = <String, String>{
          for (final doc in snapshot.docs)
            (doc.data()[contract.ItemFields.title] as String):
                (doc.data()[contract.ItemFields.status] as String),
        };

        expect(statusesByTitle['Overdue pending'], contract.ItemStatus.expired);
        expect(statusesByTitle['Future pending'], contract.ItemStatus.pending);
        expect(statusesByTitle['Keep item'], contract.ItemStatus.keep);
      },
    );

    test('last queued update wins (offline conflict simulation)', () async {
      await repository.createManualItem(
        uid: uid,
        title: 'Conflict item',
        store: StoreType.amazon,
        status: ItemStatus.pending,
        deliveredAt: DateTime(2026, 2, 24),
        returnDeadline: DateTime(2026, 3, 25),
      );

      final created = await repository.watchItems(uid: uid).first;
      expect(created.length, 1);
      final base = created.first;

      final keepUpdate = _copyWithStatus(
        item: base,
        status: ItemStatus.keep,
        updatedAt: DateTime(2026, 2, 26, 10, 00),
      );
      final returnUpdate = _copyWithStatus(
        item: base,
        status: ItemStatus.returnItem,
        updatedAt: DateTime(2026, 2, 26, 10, 01),
      );

      await repository.updateItem(keepUpdate);
      await repository.updateItem(returnUpdate);

      final latest = await repository.watchItems(uid: uid).first;
      expect(latest.length, 1);
      expect(latest.first.status, ItemStatus.returnItem);
      expect(
        latest.first.updatedAt.millisecondsSinceEpoch,
        returnUpdate.updatedAt.millisecondsSinceEpoch,
      );
    });
  });
}

ReturnItem _copyWithStatus({
  required ReturnItem item,
  required ItemStatus status,
  required DateTime updatedAt,
}) {
  return item.copyWith(status: status, updatedAt: updatedAt);
}
