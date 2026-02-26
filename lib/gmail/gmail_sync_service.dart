import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../contracts/firestore_contract.dart' as contract;
import '../items/domain/deadline_engine.dart';

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
      final upserted = await _upsertCandidate(
        uid: firebaseUser.uid,
        candidate: candidate,
      );
      if (upserted) {
        candidateCount += 1;
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
    final parsed = _parseDeliveryCandidate(candidate);
    if (parsed == null) {
      return false;
    }

    final docId = _dedupeDocId(uid: uid, parsed: parsed);

    final docRef = _firestore
        .collection(contract.FirestoreContract.users)
        .doc(uid)
        .collection(contract.UserSubcollections.items)
        .doc(docId);

    final existing = await docRef.get();
    final existingData = existing.data();

    final createdAt =
        (existingData?[contract.ItemFields.createdAt] as Timestamp?) ??
        Timestamp.now();
    final existingStatus = existingData?[contract.ItemFields.status] as String?;
    final status = _resolvedStatusForUpsert(
      existingStatus: existingStatus,
      returnDeadline: parsed.returnDeadline,
    );
    final existingMessageIds =
        existingData?[contract.ItemFields.messageIds] as List<dynamic>? ??
        const [];
    final mergedMessageIds = _mergeMessageIds(
      existing: existingMessageIds,
      incomingMessageId: candidate.messageId,
    );

    final existingOrderId =
        existingData?[contract.ItemFields.orderId] as String?;
    final mergedOrderId = parsed.orderId ?? existingOrderId;
    final existingTitle = (existingData?[contract.ItemFields.title] as String?)
        ?.trim();
    final title = parsed.title.isNotEmpty
        ? parsed.title
        : (existingTitle?.isNotEmpty == true
              ? existingTitle!
              : 'Gmail Delivery');
    final existingNormalizedTitle =
        (existingData?[contract.ItemFields.normalizedTitle] as String?)?.trim();
    final normalizedTitle = parsed.normalizedTitle.isNotEmpty
        ? parsed.normalizedTitle
        : (existingNormalizedTitle?.isNotEmpty == true
              ? existingNormalizedTitle!
              : _normalizeForDedupeKey(title));

    await docRef.set({
      contract.ItemFields.uid: uid,
      contract.ItemFields.title: title,
      contract.ItemFields.store: parsed.store,
      contract.ItemFields.status: status,
      contract.ItemFields.deliveredAt: Timestamp.fromDate(
        parsed.deliveredAtDay,
      ),
      contract.ItemFields.returnDeadline: Timestamp.fromDate(
        parsed.returnDeadline,
      ),
      contract.ItemFields.returnWindowDays: parsed.returnWindowDays,
      contract.ItemFields.createdAt: createdAt,
      contract.ItemFields.updatedAt: Timestamp.now(),
      contract.ItemFields.normalizedTitle: normalizedTitle,
      contract.ItemFields.source: contract.ItemSource.gmailSync,
      contract.ItemFields.messageIds: mergedMessageIds,
      if (mergedOrderId != null && mergedOrderId.isNotEmpty)
        contract.ItemFields.orderId: mergedOrderId,
    }, SetOptions(merge: true));

    return true;
  }

  _ParsedDelivery? _parseDeliveryCandidate(_GmailCandidate candidate) {
    final store = _inferStore(
      from: candidate.from,
      subject: candidate.subject,
      snippet: candidate.snippet,
    );
    if (store == contract.StoreType.other) {
      return null;
    }

    final content = '${candidate.subject}\n${candidate.snippet}'.toLowerCase();
    final isDelivered = _deliverySignalRegex.hasMatch(content);
    if (!isDelivered) {
      return null;
    }

    final orderId = _extractOrderId(
      store: store,
      subject: candidate.subject,
      snippet: candidate.snippet,
    );
    final title = _extractTitle(
      store: store,
      subject: candidate.subject,
      snippet: candidate.snippet,
      orderId: orderId,
    );
    final normalizedTitle = _normalizeForDedupeKey(title);
    final returnWindowDays = store == contract.StoreType.shein
        ? DeadlineEngine.sheinWindowDays
        : DeadlineEngine.defaultWindowDays;
    final deliveredAtDay = DeadlineEngine.atStartOfDay(candidate.deliveredAt);
    final returnDeadline = DeadlineEngine.calculateReturnDeadline(
      deliveredAt: deliveredAtDay,
      returnWindowDays: returnWindowDays,
    );

    return _ParsedDelivery(
      store: store,
      orderId: orderId,
      title: title,
      normalizedTitle: normalizedTitle,
      deliveredAtDay: deliveredAtDay,
      returnWindowDays: returnWindowDays,
      returnDeadline: returnDeadline,
    );
  }

  String _extractTitle({
    required String store,
    required String subject,
    required String snippet,
    required String? orderId,
  }) {
    var cleaned = subject.trim();
    if (cleaned.isEmpty) {
      cleaned = snippet.trim();
    }

    cleaned = cleaned.replaceAll(_brandNoiseRegex, ' ');
    cleaned = cleaned.replaceAll(_deliveryNoiseRegex, ' ');
    cleaned = cleaned.replaceAll(_genericOrderPatternRegex, ' ');
    if (orderId != null && orderId.isNotEmpty) {
      cleaned = cleaned.replaceAll(orderId, ' ');
    }
    cleaned = cleaned.replaceAll(_punctuationNoiseRegex, ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleaned.isNotEmpty) {
      return cleaned.length <= 200 ? cleaned : cleaned.substring(0, 200);
    }

    final storeLabel = store == contract.StoreType.shein ? 'SHEIN' : 'Amazon';
    if (orderId != null && orderId.isNotEmpty) {
      return '$storeLabel order $orderId';
    }
    return '$storeLabel delivery';
  }

  String _normalizeForDedupeKey(String raw) {
    final cleaned = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) {
      return 'delivery';
    }
    if (cleaned.length <= 120) {
      return cleaned;
    }
    return cleaned.substring(0, 120);
  }

  String _inferStore({
    required String from,
    required String subject,
    required String snippet,
  }) {
    final text =
        '${from.toLowerCase()} ${subject.toLowerCase()} ${snippet.toLowerCase()}';
    if (text.contains('amazon') || text.contains('amz')) {
      return contract.StoreType.amazon;
    }
    if (text.contains('shein')) {
      return contract.StoreType.shein;
    }
    return contract.StoreType.other;
  }

  String? _extractOrderId({
    required String store,
    required String subject,
    required String snippet,
  }) {
    final haystack = '$subject\n$snippet';

    if (store == contract.StoreType.amazon) {
      final amazonMatch = _amazonOrderIdRegex.firstMatch(haystack);
      if (amazonMatch != null) {
        return amazonMatch.group(0)?.toUpperCase();
      }
    }

    final genericMatch = _genericOrderIdRegex.firstMatch(haystack);
    final extracted = genericMatch?.group(1)?.toUpperCase();
    if (extracted == null || extracted.isEmpty) {
      return null;
    }
    if (extracted.length > 120) {
      return extracted.substring(0, 120);
    }
    return extracted;
  }

  String _dedupeDocId({required String uid, required _ParsedDelivery parsed}) {
    final orderId = parsed.orderId?.toLowerCase() ?? '';
    final key = '$uid|${parsed.store}|$orderId|${parsed.normalizedTitle}';
    final hash = _fnv1a64Hex(key);
    return 'gmail_$hash';
  }

  String _resolvedStatusForUpsert({
    required String? existingStatus,
    required DateTime returnDeadline,
  }) {
    if (existingStatus == contract.ItemStatus.keep ||
        existingStatus == contract.ItemStatus.returnItem ||
        existingStatus == contract.ItemStatus.expired) {
      return existingStatus!;
    }
    final isExpired =
        DeadlineEngine.daysRemaining(returnDeadline: returnDeadline) < 0;
    return isExpired
        ? contract.ItemStatus.expired
        : contract.ItemStatus.pending;
  }

  List<String> _mergeMessageIds({
    required List<dynamic> existing,
    required String incomingMessageId,
  }) {
    final merged = <String>[];
    for (final id in existing.whereType<String>()) {
      if (id.isNotEmpty && !merged.contains(id)) {
        merged.add(id);
      }
    }
    if (!merged.contains(incomingMessageId)) {
      merged.add(incomingMessageId);
    }
    if (merged.length <= 100) {
      return merged;
    }
    return merged.sublist(merged.length - 100);
  }

  String _fnv1a64Hex(String value) {
    const int offsetBasis = 0xcbf29ce484222325;
    const int prime = 0x100000001b3;
    const int mask64 = 0xFFFFFFFFFFFFFFFF;

    var hash = offsetBasis;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * prime) & mask64;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static final RegExp _deliverySignalRegex = RegExp(
    r'\b(delivered|delivery confirmation|package was delivered)\b',
    caseSensitive: false,
  );
  static final RegExp _amazonOrderIdRegex = RegExp(
    r'\b\d{3}-\d{7}-\d{7}\b',
    caseSensitive: false,
  );
  static final RegExp _genericOrderIdRegex = RegExp(
    r'(?:order(?:\s*(?:id|number|no\.?|#))?\s*[:#]?\s*)([A-Z0-9-]{6,30})',
    caseSensitive: false,
  );
  static final RegExp _genericOrderPatternRegex = RegExp(
    r'order(?:\s*(?:id|number|no\.?|#))?\s*[:#]?\s*[A-Z0-9-]{3,30}',
    caseSensitive: false,
  );
  static final RegExp _deliveryNoiseRegex = RegExp(
    r'\b(your|package|order|delivery|delivered|has been|was|is|out for)\b',
    caseSensitive: false,
  );
  static final RegExp _brandNoiseRegex = RegExp(
    r'\b(amazon|amazon\.com|shein)\b',
    caseSensitive: false,
  );
  static final RegExp _punctuationNoiseRegex = RegExp(r'[\|\-:_\[\]\(\),]+');
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

class _ParsedDelivery {
  const _ParsedDelivery({
    required this.store,
    required this.orderId,
    required this.title,
    required this.normalizedTitle,
    required this.deliveredAtDay,
    required this.returnWindowDays,
    required this.returnDeadline,
  });

  final String store;
  final String? orderId;
  final String title;
  final String normalizedTitle;
  final DateTime deliveredAtDay;
  final int returnWindowDays;
  final DateTime returnDeadline;
}
