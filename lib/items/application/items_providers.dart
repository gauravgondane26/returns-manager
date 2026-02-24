import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/firestore_items_repository.dart';
import '../data/items_repository.dart';
import '../domain/item_enums.dart';
import '../domain/return_item.dart';

final itemsRepositoryProvider = Provider<ItemsRepository>((ref) {
  return FirestoreItemsRepository(FirebaseFirestore.instance);
});

final currentUserIdProvider = Provider<String?>((ref) {
  return FirebaseAuth.instance.currentUser?.uid;
});

final currentUserItemsProvider = StreamProvider<List<ReturnItem>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream.value(const <ReturnItem>[]);
  }

  final repository = ref.watch(itemsRepositoryProvider);
  return repository.watchItems(uid: uid);
});

final allItemsProvider = Provider<AsyncValue<List<ReturnItem>>>((ref) {
  final itemsAsync = ref.watch(currentUserItemsProvider);
  return itemsAsync.whenData((items) {
    final sorted = [...items];
    sorted.sort((a, b) => a.returnDeadline.compareTo(b.returnDeadline));
    return sorted;
  });
});

final homeItemsProvider = Provider<AsyncValue<List<ReturnItem>>>((ref) {
  final itemsAsync = ref.watch(currentUserItemsProvider);
  return itemsAsync.whenData((items) {
    final inPeriodItems = items.where((item) => item.isInReturnPeriod).toList();
    inPeriodItems.sort((a, b) => a.returnDeadline.compareTo(b.returnDeadline));
    return inPeriodItems;
  });
});

final calendarItemsProvider = Provider<AsyncValue<List<ReturnItem>>>((ref) {
  final itemsAsync = ref.watch(currentUserItemsProvider);
  return itemsAsync.whenData((items) {
    final inPeriodItems = items.where((item) => item.isInReturnPeriod).toList();
    inPeriodItems.sort((a, b) => a.returnDeadline.compareTo(b.returnDeadline));
    return inPeriodItems;
  });
});

final keepsItemsProvider = Provider<AsyncValue<List<ReturnItem>>>((ref) {
  final itemsAsync = ref.watch(currentUserItemsProvider);
  return itemsAsync.whenData((items) {
    return items.where((item) => item.status == ItemStatus.keep).toList();
  });
});

final returnsItemsProvider = Provider<AsyncValue<List<ReturnItem>>>((ref) {
  final itemsAsync = ref.watch(currentUserItemsProvider);
  return itemsAsync.whenData((items) {
    return items.where((item) => item.status == ItemStatus.returnItem).toList();
  });
});

final expiredItemsProvider = Provider<AsyncValue<List<ReturnItem>>>((ref) {
  final itemsAsync = ref.watch(currentUserItemsProvider);
  return itemsAsync.whenData((items) {
    return items
        .where(
          (item) =>
              item.status == ItemStatus.expired ||
              (item.status == ItemStatus.pending && !item.isInReturnPeriod),
        )
        .toList();
  });
});
