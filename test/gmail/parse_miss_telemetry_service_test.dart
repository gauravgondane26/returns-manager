import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:returnsmanager/contracts/firestore_contract.dart' as contract;
import 'package:returnsmanager/gmail/parse_miss_telemetry_service.dart';

void main() {
  group('ParseMissTelemetryService', () {
    late FakeFirebaseFirestore firestore;
    late ParseMissTelemetryService service;

    const uid = 'user_telemetry';
    const messageId = 'm-123';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = ParseMissTelemetryService(firestore: firestore);
    });

    test('tracks parse miss in user telemetry collection', () async {
      await service.trackParseMiss(
        uid: uid,
        messageId: messageId,
        reason: 'missing_delivery_signal',
        storeHint: 'amazon',
        from: 'Amazon Shipping <shipment-tracking@amazon.com>',
        subject: 'Your Amazon package update',
        snippet: 'Package update only, no delivered signal.',
      );

      final doc = await firestore
          .collection(contract.FirestoreContract.users)
          .doc(uid)
          .collection(contract.UserSubcollections.telemetry)
          .doc('parse_miss_$messageId')
          .get();
      final data = doc.data()!;

      expect(data[contract.TelemetryFields.uid], uid);
      expect(
        data[contract.TelemetryFields.type],
        contract.TelemetryType.gmailParseMiss,
      );
      expect(data[contract.TelemetryFields.messageId], messageId);
      expect(data[contract.TelemetryFields.reason], 'missing_delivery_signal');
      expect(data[contract.TelemetryFields.storeHint], 'amazon');
      expect(data[contract.TelemetryFields.fromDomain], 'amazon.com');
      expect(data[contract.TelemetryFields.subjectSample], isNotEmpty);
      expect(data[contract.TelemetryFields.snippetSample], isNotEmpty);
      expect(data[contract.TelemetryFields.createdAt], isNotNull);
      expect(data[contract.TelemetryFields.updatedAt], isNotNull);
    });

    test('updates existing parse miss without changing createdAt', () async {
      await service.trackParseMiss(
        uid: uid,
        messageId: messageId,
        reason: 'missing_delivery_signal',
        storeHint: 'amazon',
        from: 'shipment-tracking@amazon.com',
        subject: 'A',
        snippet: 'B',
      );

      final firstDoc = await firestore
          .collection(contract.FirestoreContract.users)
          .doc(uid)
          .collection(contract.UserSubcollections.telemetry)
          .doc('parse_miss_$messageId')
          .get();
      final firstCreatedAt = firstDoc
          .data()![contract.TelemetryFields.createdAt];

      await service.trackParseMiss(
        uid: uid,
        messageId: messageId,
        reason: 'missing_delivery_signal',
        storeHint: 'amazon',
        from: 'shipment-tracking@amazon.com',
        subject: 'A changed',
        snippet: 'B changed',
      );

      final secondDoc = await firestore
          .collection(contract.FirestoreContract.users)
          .doc(uid)
          .collection(contract.UserSubcollections.telemetry)
          .doc('parse_miss_$messageId')
          .get();
      final secondData = secondDoc.data()!;

      expect(secondData[contract.TelemetryFields.createdAt], firstCreatedAt);
      expect(secondData[contract.TelemetryFields.subjectSample], 'A changed');
      expect(secondData[contract.TelemetryFields.snippetSample], 'B changed');
    });
  });
}
