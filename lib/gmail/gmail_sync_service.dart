import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../contracts/firestore_contract.dart' as contract;

class GmailSyncResult {
  const GmailSyncResult({
    required this.fetchedMessages,
    required this.candidatesFound,
    required this.upserts,
  });

  final int fetchedMessages;
  final int candidatesFound;
  final int upserts;
}

class GmailSyncService {
  GmailSyncService({FirebaseFirestore? firestore, GoogleSignIn? googleSignIn})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _googleSignIn =
          googleSignIn ??
          GoogleSignIn(
            scopes: const [
              'email',
              'https://www.googleapis.com/auth/gmail.readonly',
            ],
          );

  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  static const _gmailReadonlyScope =
      'https://www.googleapis.com/auth/gmail.readonly';

  Future<GmailSyncResult> syncDeliveries({int maxResults = 12}) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw Exception('You must be signed in to sync Gmail.');
    }

    var account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently();
    account ??= await _googleSignIn.signIn();
    if (account == null) {
      throw Exception('Google account not available.');
    }

    final granted = await _googleSignIn.requestScopes(const [
      _gmailReadonlyScope,
    ]);
    if (!granted) {
      throw Exception('Gmail read permission was not granted.');
    }

    account = _googleSignIn.currentUser ?? account;
    final headers = await account.authHeaders;

    final messageIds = await _fetchMessageIds(
      headers: headers,
      maxResults: maxResults,
    );

    var candidateCount = 0;
    var upserts = 0;
    for (final messageId in messageIds) {
      final candidate = await _fetchCandidateMessage(
        headers: headers,
        messageId: messageId,
      );
      if (candidate == null) {
        continue;
      }
      candidateCount += 1;

      final upserted = await _upsertCandidate(
        uid: firebaseUser.uid,
        candidate: candidate,
      );
      if (upserted) {
        upserts += 1;
      }
    }

    return GmailSyncResult(
      fetchedMessages: messageIds.length,
      candidatesFound: candidateCount,
      upserts: upserts,
    );
  }

  Future<List<String>> _fetchMessageIds({
    required Map<String, String> headers,
    required int maxResults,
  }) async {
    final uri = Uri.https(
      'gmail.googleapis.com',
      '/gmail/v1/users/me/messages',
      {'q': _deliveryQuery(), 'maxResults': maxResults.clamp(1, 25).toString()},
    );

    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      final bodyLower = response.body.toLowerCase();
      if (response.statusCode == 403 &&
          (bodyLower.contains('accessnotconfigured') ||
              bodyLower.contains('service_disabled') ||
              bodyLower.contains('gmail api has not been used'))) {
        throw Exception(
          'Gmail API is not enabled for this Google Cloud project. '
          'Enable Gmail API in Google Cloud Console and retry in a few minutes.',
        );
      }
      if (response.statusCode == 401) {
        throw Exception(
          'Gmail authorization expired. Sign out/in again and grant Gmail access.',
        );
      }
      throw Exception('Gmail sync failed (HTTP ${response.statusCode}).');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final messages = payload['messages'] as List<dynamic>? ?? const [];
    return messages
        .map((entry) => (entry as Map<String, dynamic>)['id'] as String?)
        .whereType<String>()
        .toList();
  }

  String _deliveryQuery() {
    return [
      'newer_than:120d',
      '(from:amazon OR from:shein OR from:amz OR from:shein.com)',
      '(subject:delivered OR subject:delivery OR subject:"package was delivered")',
    ].join(' ');
  }

  Future<_GmailCandidate?> _fetchCandidateMessage({
    required Map<String, String> headers,
    required String messageId,
  }) async {
    final uri = Uri.parse(
      'https://gmail.googleapis.com/gmail/v1/users/me/messages/'
      '$messageId?format=metadata'
      '&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date',
    );
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final payload = data['payload'] as Map<String, dynamic>? ?? const {};
    final headersList = payload['headers'] as List<dynamic>? ?? const [];

    String subject = '';
    String from = '';
    String date = '';
    for (final headerEntry in headersList) {
      final header = headerEntry as Map<String, dynamic>;
      final name = (header['name'] as String? ?? '').toLowerCase();
      final value = header['value'] as String? ?? '';
      if (name == 'subject') {
        subject = value;
      } else if (name == 'from') {
        from = value;
      } else if (name == 'date') {
        date = value;
      }
    }

    if (subject.trim().isEmpty && from.trim().isEmpty) {
      return null;
    }

    final snippet = data['snippet'] as String? ?? '';
    final internalDateMs = int.tryParse('${data['internalDate'] ?? ''}');
    final deliveredAt = internalDateMs == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(internalDateMs);

    return _GmailCandidate(
      messageId: messageId,
      subject: subject,
      from: from,
      date: date,
      snippet: snippet,
      deliveredAt: deliveredAt,
    );
  }

  Future<bool> _upsertCandidate({
    required String uid,
    required _GmailCandidate candidate,
  }) async {
    final store = _inferStore(from: candidate.from, subject: candidate.subject);

    final returnWindowDays = store == contract.StoreType.shein ? 35 : 30;
    final deliveredAtDay = DateTime(
      candidate.deliveredAt.year,
      candidate.deliveredAt.month,
      candidate.deliveredAt.day,
    );
    final returnDeadline = deliveredAtDay.add(Duration(days: returnWindowDays));
    final title = _normalizeTitle(candidate.subject);

    final docRef = _firestore
        .collection(contract.FirestoreContract.users)
        .doc(uid)
        .collection(contract.UserSubcollections.items)
        .doc('gmail_${candidate.messageId}');

    final existing = await docRef.get();
    final createdAt = existing.exists
        ? (existing.data()?[contract.ItemFields.createdAt] as Timestamp?) ??
              Timestamp.now()
        : Timestamp.now();

    await docRef.set({
      contract.ItemFields.uid: uid,
      contract.ItemFields.title: title,
      contract.ItemFields.store: store,
      contract.ItemFields.status: contract.ItemStatus.pending,
      contract.ItemFields.deliveredAt: Timestamp.fromDate(deliveredAtDay),
      contract.ItemFields.returnDeadline: Timestamp.fromDate(returnDeadline),
      contract.ItemFields.returnWindowDays: returnWindowDays,
      contract.ItemFields.createdAt: createdAt,
      contract.ItemFields.updatedAt: Timestamp.now(),
      contract.ItemFields.normalizedTitle: title.toLowerCase(),
      contract.ItemFields.source: contract.ItemSource.gmailSync,
      contract.ItemFields.messageIds: [candidate.messageId],
    });

    return true;
  }

  String _normalizeTitle(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) {
      return 'Gmail Delivery';
    }
    if (cleaned.length <= 200) {
      return cleaned;
    }
    return cleaned.substring(0, 200);
  }

  String _inferStore({required String from, required String subject}) {
    final text = '${from.toLowerCase()} ${subject.toLowerCase()}';
    if (text.contains('amazon') || text.contains('amz')) {
      return contract.StoreType.amazon;
    }
    if (text.contains('shein')) {
      return contract.StoreType.shein;
    }
    return contract.StoreType.other;
  }
}

class _GmailCandidate {
  const _GmailCandidate({
    required this.messageId,
    required this.subject,
    required this.from,
    required this.date,
    required this.snippet,
    required this.deliveredAt,
  });

  final String messageId;
  final String subject;
  final String from;
  final String date;
  final String snippet;
  final DateTime deliveredAt;
}
