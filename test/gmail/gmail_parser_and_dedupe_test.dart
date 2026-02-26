import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:returnsmanager/gmail/gmail_sync_service.dart';

void main() {
  group('Gmail parser fixtures', () {
    final service = GmailSyncService(firestore: FakeFirebaseFirestore());

    test('parses Amazon delivered fixture deterministically', () {
      final fixture = _readFixture('amazon_delivered.json');
      final parsed = service.parseCandidateForTest(
        subject: fixture['subject'] as String,
        from: fixture['from'] as String,
        snippet: fixture['snippet'] as String,
        deliveredAt: DateTime.parse(fixture['deliveredAt'] as String),
      );

      expect(parsed, isNotNull);
      final expected = fixture['expected'] as Map<String, dynamic>;
      expect(parsed!['store'], expected['store']);
      expect(parsed['orderId'], expected['orderId']);
      expect(parsed['title'], expected['title']);
      expect(parsed['normalizedTitle'], expected['normalizedTitle']);
      expect(parsed['returnWindowDays'], expected['returnWindowDays']);
      expect(
        _dateKey(parsed['returnDeadline'] as DateTime),
        expected['returnDeadlineDate'],
      );
    });

    test('parses SHEIN delivered fixture deterministically', () {
      final fixture = _readFixture('shein_delivered.json');
      final parsed = service.parseCandidateForTest(
        subject: fixture['subject'] as String,
        from: fixture['from'] as String,
        snippet: fixture['snippet'] as String,
        deliveredAt: DateTime.parse(fixture['deliveredAt'] as String),
      );

      expect(parsed, isNotNull);
      final expected = fixture['expected'] as Map<String, dynamic>;
      expect(parsed!['store'], expected['store']);
      expect(parsed['orderId'], expected['orderId']);
      expect(parsed['title'], expected['title']);
      expect(parsed['normalizedTitle'], expected['normalizedTitle']);
      expect(parsed['returnWindowDays'], expected['returnWindowDays']);
      expect(
        _dateKey(parsed['returnDeadline'] as DateTime),
        expected['returnDeadlineDate'],
      );
    });

    test('ignores non-delivery fixture', () {
      final fixture = _readFixture('non_delivery.json');
      final parsed = service.parseCandidateForTest(
        subject: fixture['subject'] as String,
        from: fixture['from'] as String,
        snippet: fixture['snippet'] as String,
        deliveredAt: DateTime.parse(fixture['deliveredAt'] as String),
      );

      expect(parsed, isNull);
    });
  });

  group('Gmail dedupe helpers', () {
    final service = GmailSyncService(firestore: FakeFirebaseFirestore());

    test('dedupe doc id is deterministic', () {
      final first = service.dedupeDocIdForTest(
        uid: 'u1',
        store: 'amazon',
        orderId: '123-1234567-1234567',
        normalizedTitle: 'amazon order 123 1234567 1234567',
      );
      final second = service.dedupeDocIdForTest(
        uid: 'u1',
        store: 'amazon',
        orderId: '123-1234567-1234567',
        normalizedTitle: 'amazon order 123 1234567 1234567',
      );

      expect(first, second);
    });

    test('dedupe doc id changes when order id changes', () {
      final first = service.dedupeDocIdForTest(
        uid: 'u1',
        store: 'amazon',
        orderId: '123-1234567-1234567',
        normalizedTitle: 'amazon order',
      );
      final second = service.dedupeDocIdForTest(
        uid: 'u1',
        store: 'amazon',
        orderId: '555-7654321-1234567',
        normalizedTitle: 'amazon order',
      );

      expect(first, isNot(second));
    });

    test('mergeMessageIds deduplicates and caps to 100', () {
      final existing = List.generate(101, (i) => 'm$i');
      final merged = service.mergeMessageIdsForTest(
        existing: existing,
        incomingMessageId: 'm100',
      );

      expect(merged.length, 100);
      expect(merged.first, 'm1');
      expect(merged.last, 'm100');
      expect(merged.where((id) => id == 'm100').length, 1);
    });
  });
}

Map<String, dynamic> _readFixture(String fileName) {
  final file = File('test/fixtures/gmail/$fileName');
  final raw = file.readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

String _dateKey(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
