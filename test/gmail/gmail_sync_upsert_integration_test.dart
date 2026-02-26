import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:returnsmanager/contracts/firestore_contract.dart' as contract;
import 'package:returnsmanager/gmail/gmail_sync_service.dart';

void main() {
  group('Gmail sync upsert integration', () {
    late FakeFirebaseFirestore firestore;
    late GmailSyncService service;

    const uid = 'user_1';

    CollectionReference<Map<String, dynamic>> itemsCollection() {
      return firestore
          .collection(contract.FirestoreContract.users)
          .doc(uid)
          .collection(contract.UserSubcollections.items);
    }

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = GmailSyncService(firestore: firestore);
    });

    test('repeated matching deliveries upsert into one document', () async {
      final first = await service.upsertCandidateForTest(
        uid: uid,
        messageId: 'msg-1',
        subject: 'Your Amazon.com order 123-1234567-1234567 was delivered',
        from: 'Amazon <shipment-tracking@amazon.com>',
        snippet: 'Package was delivered.',
        deliveredAt: DateTime(2026, 2, 24, 13, 10),
      );
      final second = await service.upsertCandidateForTest(
        uid: uid,
        messageId: 'msg-2',
        subject: 'Your Amazon.com order 123-1234567-1234567 was delivered',
        from: 'Amazon <shipment-tracking@amazon.com>',
        snippet: 'Package was delivered.',
        deliveredAt: DateTime(2026, 2, 24, 13, 15),
      );

      expect(first, isTrue);
      expect(second, isTrue);

      final snapshot = await itemsCollection().get();
      expect(snapshot.docs.length, 1);

      final data = snapshot.docs.first.data();
      expect(data[contract.ItemFields.orderId], '123-1234567-1234567');
      expect(data[contract.ItemFields.source], contract.ItemSource.gmailSync);

      final messageIds = (data[contract.ItemFields.messageIds] as List<dynamic>)
          .cast<String>();
      expect(messageIds, containsAll(<String>['msg-1', 'msg-2']));
      expect(messageIds.length, 2);
    });

    test('upsert preserves user decision status (keep)', () async {
      await service.upsertCandidateForTest(
        uid: uid,
        messageId: 'msg-a',
        subject: 'SHEIN order SHN123456 was delivered',
        from: 'SHEIN <notice@shein.com>',
        snippet: 'Delivery confirmation for your package.',
        deliveredAt: DateTime(2026, 2, 24, 9, 30),
      );

      final initialSnapshot = await itemsCollection().get();
      final docRef = initialSnapshot.docs.first.reference;
      await docRef.update(<String, dynamic>{
        contract.ItemFields.status: contract.ItemStatus.keep,
        contract.ItemFields.updatedAt: Timestamp.now(),
      });

      await service.upsertCandidateForTest(
        uid: uid,
        messageId: 'msg-b',
        subject: 'SHEIN order SHN123456 was delivered',
        from: 'SHEIN <notice@shein.com>',
        snippet: 'Delivery confirmation for your package.',
        deliveredAt: DateTime(2026, 2, 24, 10, 30),
      );

      final snapshot = await docRef.get();
      final data = snapshot.data()!;
      expect(data[contract.ItemFields.status], contract.ItemStatus.keep);
      final messageIds = (data[contract.ItemFields.messageIds] as List<dynamic>)
          .cast<String>();
      expect(messageIds, containsAll(<String>['msg-a', 'msg-b']));
    });
  });
}
