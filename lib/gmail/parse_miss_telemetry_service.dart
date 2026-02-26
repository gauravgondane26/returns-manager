import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meta/meta.dart';

import '../contracts/firestore_contract.dart' as contract;

class ParseMissTelemetryService {
  ParseMissTelemetryService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> trackParseMiss({
    required String uid,
    required String messageId,
    required String reason,
    required String storeHint,
    required String from,
    required String subject,
    required String snippet,
  }) async {
    final docRef = _firestore
        .collection(contract.FirestoreContract.users)
        .doc(uid)
        .collection(contract.UserSubcollections.telemetry)
        .doc('parse_miss_$messageId');

    final now = Timestamp.now();
    final existing = await docRef.get();
    final createdAt =
        (existing.data()?[contract.TelemetryFields.createdAt] as Timestamp?) ??
        now;

    await docRef.set({
      contract.TelemetryFields.uid: uid,
      contract.TelemetryFields.type: contract.TelemetryType.gmailParseMiss,
      contract.TelemetryFields.messageId: messageId,
      contract.TelemetryFields.reason: _limit(reason, 80),
      contract.TelemetryFields.storeHint: _limit(storeHint, 32),
      contract.TelemetryFields.fromDomain: _extractDomain(from),
      contract.TelemetryFields.subjectSample: _limit(_sanitize(subject), 160),
      contract.TelemetryFields.snippetSample: _limit(_sanitize(snippet), 200),
      contract.TelemetryFields.createdAt: createdAt,
      contract.TelemetryFields.updatedAt: now,
    }, SetOptions(merge: true));
  }

  @visibleForTesting
  String extractDomainForTest(String fromValue) => _extractDomain(fromValue);

  String _extractDomain(String fromValue) {
    final lower = fromValue.toLowerCase();
    final emailMatch = RegExp(
      r'([a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,})',
    ).firstMatch(lower);
    final email = emailMatch?.group(1);
    if (email == null) {
      return 'unknown';
    }
    final parts = email.split('@');
    if (parts.length != 2 || parts[1].isEmpty) {
      return 'unknown';
    }
    return _limit(parts[1], 120);
  }

  String _sanitize(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _limit(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength);
  }
}
