import '../domain/return_item.dart';

abstract class ItemsRepository {
  Stream<List<ReturnItem>> watchItems({required String uid});
}
