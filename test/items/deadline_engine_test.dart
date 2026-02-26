import 'package:flutter_test/flutter_test.dart';
import 'package:returnsmanager/items/domain/deadline_engine.dart';
import 'package:returnsmanager/items/domain/item_enums.dart';

void main() {
  group('DeadlineEngine', () {
    test('calculates inclusive return deadline from return window days', () {
      final deliveredAt = DateTime(2026, 2, 24, 15, 30);
      final deadline = DeadlineEngine.calculateReturnDeadline(
        deliveredAt: deliveredAt,
        returnWindowDays: 30,
      );

      expect(deadline, DateTime(2026, 3, 25));
    });

    test('calculates return window days from delivered and deadline', () {
      final days = DeadlineEngine.calculateReturnWindowDays(
        deliveredAt: DateTime(2026, 2, 24),
        returnDeadline: DateTime(2026, 3, 25),
      );

      expect(days, 30);
    });

    test('resolves pending to expired when deadline has passed', () {
      final resolved = DeadlineEngine.resolveStatus(
        status: ItemStatus.pending,
        returnDeadline: DateTime(2026, 2, 20),
        now: DateTime(2026, 2, 26),
      );

      expect(resolved, ItemStatus.expired);
    });

    test('resolves expired back to pending when deadline is moved forward', () {
      final resolved = DeadlineEngine.resolveStatus(
        status: ItemStatus.expired,
        returnDeadline: DateTime(2026, 2, 28),
        now: DateTime(2026, 2, 26),
      );

      expect(resolved, ItemStatus.pending);
    });

    test('keeps keep/return statuses unchanged by deadline checks', () {
      final keep = DeadlineEngine.resolveStatus(
        status: ItemStatus.keep,
        returnDeadline: DateTime(2026, 2, 20),
        now: DateTime(2026, 2, 26),
      );
      final returnItem = DeadlineEngine.resolveStatus(
        status: ItemStatus.returnItem,
        returnDeadline: DateTime(2026, 2, 20),
        now: DateTime(2026, 2, 26),
      );

      expect(keep, ItemStatus.keep);
      expect(returnItem, ItemStatus.returnItem);
    });

    test('defaults return windows by store', () {
      expect(
        DeadlineEngine.defaultWindowForStore(StoreType.amazon),
        DeadlineEngine.defaultWindowDays,
      );
      expect(
        DeadlineEngine.defaultWindowForStore(StoreType.other),
        DeadlineEngine.defaultWindowDays,
      );
      expect(
        DeadlineEngine.defaultWindowForStore(StoreType.shein),
        DeadlineEngine.sheinWindowDays,
      );
    });
  });
}
