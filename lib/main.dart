import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:table_calendar/table_calendar.dart';

import 'calendar_export/calendar_export_providers.dart';
import 'core/app_error_mapper.dart';
import 'firebase_options.dart';
import 'gmail/gmail_sync_service.dart';
import 'items/application/items_providers.dart';
import 'items/domain/deadline_engine.dart';
import 'items/domain/item_enums.dart';
import 'items/domain/return_item.dart';
import 'reminders/reminder_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (!kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }
  runApp(const ProviderScope(child: ReturnsManagerApp()));
}

class ReturnsManagerApp extends StatelessWidget {
  const ReturnsManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Returns Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data == null) {
          return const SignInPage();
        }

        return const AppShell();
      },
    );
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (error) {
      final mapped = mapToUserFacingError(error);
      setState(() {
        _errorMessage = mapped.actionHint == null
            ? mapped.message
            : '${mapped.message} ${mapped.actionHint}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Returns Manager')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Sign in to continue',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    child: Text(
                      _isLoading ? 'Signing in...' : 'Continue with Google',
                    ),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentTabIndex = 0;
  bool _isSyncingGmail = false;
  bool _isReminderSyncEnabled = false;
  bool _isCalendarExportEnabled = false;
  Set<String> _trackedReminderItemIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyDeadlineTransitions();
      unawaited(_initializeReminderScheduler());
      unawaited(_initializeCalendarExport());
    });
  }

  Future<void> _applyDeadlineTransitions() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final repository = ref.read(itemsRepositoryProvider);
    try {
      await repository.expireOverduePendingItems(uid: uid);
    } catch (_) {}
  }

  Future<void> _signOut() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final scheduler = ref.read(reminderSchedulerProvider);
    for (final itemId in _trackedReminderItemIds) {
      await scheduler.cancelForItem(itemId);
    }
    _trackedReminderItemIds = <String>{};

    if (uid != null) {
      final calendarExport = ref.read(calendarExportServiceProvider);
      await calendarExport.clearExportedEvents(uid: uid);
    }

    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _initializeReminderScheduler() async {
    try {
      final scheduler = ref.read(reminderSchedulerProvider);
      await scheduler.initialize();
      if (!mounted) {
        return;
      }

      setState(() {
        _isReminderSyncEnabled = true;
      });

      final itemsState = ref.read(currentUserItemsProvider);
      itemsState.whenData((items) {
        unawaited(_syncRemindersFromItems(items));
      });
    } catch (_) {}
  }

  Future<void> _syncRemindersFromItems(List<ReturnItem> items) async {
    if (!_isReminderSyncEnabled) {
      return;
    }

    final scheduler = ref.read(reminderSchedulerProvider);
    final currentIds = items.map((item) => item.id).toSet();
    final removedIds = _trackedReminderItemIds.difference(currentIds);
    for (final removedId in removedIds) {
      await scheduler.cancelForItem(removedId);
    }

    await scheduler.syncForItems(items);
    _trackedReminderItemIds = currentIds;
  }

  Future<void> _initializeCalendarExport() async {
    try {
      final exportService = ref.read(calendarExportServiceProvider);
      await exportService.initialize();
      if (!mounted) {
        return;
      }
      setState(() {
        _isCalendarExportEnabled = true;
      });

      final itemsState = ref.read(currentUserItemsProvider);
      itemsState.whenData((items) {
        unawaited(_syncCalendarExportFromItems(items));
      });
    } catch (_) {}
  }

  Future<void> _syncCalendarExportFromItems(List<ReturnItem> items) async {
    if (!_isCalendarExportEnabled) {
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final exportService = ref.read(calendarExportServiceProvider);
    await exportService.syncPendingItems(uid: uid, items: items);
  }

  Future<void> _openCreateItem() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ItemEditorPage()));
  }

  Future<void> _openEditItem(ReturnItem item) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ItemEditorPage(item: item)));
  }

  Future<void> _refreshItems() async {
    ref.invalidate(currentUserItemsProvider);
    await ref.read(currentUserItemsProvider.future);
  }

  Future<void> _syncGmail() async {
    if (_isSyncingGmail) {
      return;
    }

    setState(() {
      _isSyncingGmail = true;
    });

    try {
      final result = await GmailSyncService().syncDeliveries();
      if (!mounted) {
        return;
      }
      final parseMissLabel = result.parseMisses > 0
          ? ', ${result.parseMisses} parse miss(es)'
          : '';
      final failedLabel = result.failedMessages > 0
          ? ', ${result.failedMessages} failed message(s)'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gmail sync done: ${result.upserts} upsert(s), '
            '${result.candidatesFound} candidate(s), '
            '${result.fetchedMessages} fetched'
            '$parseMissLabel'
            '$failedLabel'
            ' in ${result.elapsedMs}ms.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final mapped = mapToUserFacingError(error);
      final message = mapped.actionHint == null
          ? mapped.message
          : '${mapped.message} ${mapped.actionHint}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(label: 'Retry', onPressed: _syncGmail),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingGmail = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<ReturnItem>>>(currentUserItemsProvider, (
      _,
      next,
    ) {
      next.whenData((items) {
        unawaited(_syncRemindersFromItems(items));
        unawaited(_syncCalendarExportFromItems(items));
      });
    });

    final tabTitles = ['Home', 'Calendar', 'Decided'];
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(tabTitles[_currentTabIndex]),
        actions: [
          IconButton(
            tooltip: 'Sync Gmail deliveries',
            onPressed: _isSyncingGmail ? null : _syncGmail,
            icon: _isSyncingGmail
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
          TextButton(onPressed: _signOut, child: const Text('Sign out')),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _currentTabIndex,
              children: [
                HomeTabView(onItemTap: _openEditItem, onRetry: _refreshItems),
                CalendarTabView(
                  onItemTap: _openEditItem,
                  onRetry: _refreshItems,
                ),
                DecidedTabView(
                  onItemTap: _openEditItem,
                  onRetry: _refreshItems,
                ),
              ],
            ),
          ),
          if (user?.email != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: Text(
                'Signed in as ${user!.email}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _currentTabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _openCreateItem,
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (value) {
          setState(() {
            _currentTabIndex = value;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Decided',
          ),
        ],
      ),
    );
  }
}

class HomeTabView extends ConsumerWidget {
  const HomeTabView({
    required this.onItemTap,
    required this.onRetry,
    super.key,
  });

  final ValueChanged<ReturnItem> onItemTap;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(homeItemsProvider);

    Future<bool> handleSwipeStatus({
      required ReturnItem item,
      required ItemStatus targetStatus,
    }) async {
      final actionLabel = targetStatus == ItemStatus.keep ? 'Keep' : 'Return';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('$actionLabel item?'),
            content: Text('Set "${item.title}" to ${targetStatus.label}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return false;
      }

      final repository = ref.read(itemsRepositoryProvider);
      final updated = item.copyWith(
        status: targetStatus,
        updatedAt: DateTime.now(),
      );

      try {
        await repository.updateItem(updated);
      } catch (error) {
        if (!context.mounted) {
          return false;
        }
        _showFailureSnackBar(
          context,
          error: error,
          fallbackPrefix: 'Status update failed',
        );
        return false;
      }

      if (!context.mounted) {
        return true;
      }

      final statusLabel = targetStatus == ItemStatus.keep
          ? 'Marked as Keep'
          : 'Marked for Return';

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(statusLabel)));
      return true;
    }

    return ItemsAsyncList(
      itemsAsync: itemsAsync,
      emptyIcon: Icons.shopping_bag_outlined,
      emptyTitle: 'No active items',
      emptySubtitle: 'Items in their return period will appear here.',
      showDaysRemaining: true,
      onItemTap: onItemTap,
      onSwipeRight: (item) =>
          handleSwipeStatus(item: item, targetStatus: ItemStatus.keep),
      onSwipeLeft: (item) =>
          handleSwipeStatus(item: item, targetStatus: ItemStatus.returnItem),
      onRetry: onRetry,
    );
  }
}

class CalendarTabView extends ConsumerStatefulWidget {
  const CalendarTabView({
    required this.onItemTap,
    required this.onRetry,
    super.key,
  });

  final ValueChanged<ReturnItem> onItemTap;
  final Future<void> Function() onRetry;

  @override
  ConsumerState<CalendarTabView> createState() => _CalendarTabViewState();
}

class _CalendarTabViewState extends ConsumerState<CalendarTabView> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  static const _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  List<ReturnItem> _itemsForDay(List<ReturnItem> items, DateTime day) {
    final normalizedDay = _normalizeDate(day);
    final filtered = items.where((item) {
      return _normalizeDate(item.returnDeadline) == normalizedDay;
    }).toList();
    filtered.sort((a, b) => a.returnDeadline.compareTo(b.returnDeadline));
    return filtered;
  }

  String _formatDate(DateTime date) {
    return '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(calendarItemsProvider);
    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) {
        return AsyncErrorState(
          message: 'Could not load calendar.',
          error: error,
          onRetry: widget.onRetry,
        );
      },
      data: (items) {
        final selectedDayItems = _itemsForDay(items, _selectedDay);
        final selectedDayLabel = _formatDate(_selectedDay);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: TableCalendar<ReturnItem>(
                    firstDay: DateTime.now().subtract(
                      const Duration(days: 365),
                    ),
                    lastDay: DateTime.now().add(const Duration(days: 365 * 2)),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    eventLoader: (day) => _itemsForDay(items, day),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                    ),
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      todayDecoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      markerDecoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                    },
                    onPageChanged: (focusedDay) {
                      setState(() {
                        _focusedDay = focusedDay;
                      });
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selectedDayLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${selectedDayItems.length} item(s)',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: selectedDayItems.isEmpty
                  ? EmptyState(
                      icon: Icons.event_busy_outlined,
                      title: 'No deadlines on this day',
                      subtitle:
                          'Pick another date with a marker to view return items.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: selectedDayItems.length,
                      itemBuilder: (context, index) {
                        return ItemCard(
                          item: selectedDayItems[index],
                          showDaysRemaining: true,
                          onTap: () =>
                              widget.onItemTap(selectedDayItems[index]),
                        );
                      },
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class DecidedTabView extends StatelessWidget {
  const DecidedTabView({
    required this.onItemTap,
    required this.onRetry,
    super.key,
  });

  final ValueChanged<ReturnItem> onItemTap;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: 'Keeps'),
              Tab(text: 'Returns'),
              Tab(text: 'Expired'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                KeepsTabView(onItemTap: onItemTap, onRetry: onRetry),
                ReturnsTabView(onItemTap: onItemTap, onRetry: onRetry),
                ExpiredTabView(onItemTap: onItemTap, onRetry: onRetry),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class KeepsTabView extends ConsumerWidget {
  const KeepsTabView({
    required this.onItemTap,
    required this.onRetry,
    super.key,
  });

  final ValueChanged<ReturnItem> onItemTap;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(keepsItemsProvider);
    return ItemsAsyncList(
      itemsAsync: itemsAsync,
      emptyIcon: Icons.favorite_border,
      emptyTitle: 'No kept items',
      emptySubtitle: 'Items marked to keep will appear here.',
      onItemTap: onItemTap,
      onRetry: onRetry,
    );
  }
}

class ReturnsTabView extends ConsumerWidget {
  const ReturnsTabView({
    required this.onItemTap,
    required this.onRetry,
    super.key,
  });

  final ValueChanged<ReturnItem> onItemTap;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(returnsItemsProvider);
    return ItemsAsyncList(
      itemsAsync: itemsAsync,
      emptyIcon: Icons.assignment_return_outlined,
      emptyTitle: 'No return items',
      emptySubtitle: 'Items marked for return will appear here.',
      onItemTap: onItemTap,
      onRetry: onRetry,
    );
  }
}

class ExpiredTabView extends ConsumerWidget {
  const ExpiredTabView({
    required this.onItemTap,
    required this.onRetry,
    super.key,
  });

  final ValueChanged<ReturnItem> onItemTap;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(expiredItemsProvider);
    return ItemsAsyncList(
      itemsAsync: itemsAsync,
      emptyIcon: Icons.hourglass_disabled_outlined,
      emptyTitle: 'No expired items',
      emptySubtitle: 'Expired return windows will appear here.',
      onItemTap: onItemTap,
      onRetry: onRetry,
    );
  }
}

class ItemsAsyncList extends StatelessWidget {
  const ItemsAsyncList({
    required this.itemsAsync,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.onItemTap,
    this.onSwipeRight,
    this.onSwipeLeft,
    this.showDaysRemaining = false,
    this.onRetry,
    super.key,
  });

  final AsyncValue<List<ReturnItem>> itemsAsync;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;
  final ValueChanged<ReturnItem> onItemTap;
  final Future<bool> Function(ReturnItem item)? onSwipeRight;
  final Future<bool> Function(ReturnItem item)? onSwipeLeft;
  final bool showDaysRemaining;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) {
        return AsyncErrorState(
          message: 'Could not load items.',
          error: error,
          onRetry: onRetry,
        );
      },
      data: (items) {
        final onRefresh = onRetry ?? () async {};

        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 420,
                  child: EmptyState(
                    icon: emptyIcon,
                    title: emptyTitle,
                    subtitle: emptySubtitle,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final card = ItemCard(
                item: item,
                showDaysRemaining: showDaysRemaining,
                onTap: () => onItemTap(item),
              );

              final dismissDirection = _dismissDirection();
              if (dismissDirection == DismissDirection.none) {
                return card;
              }

              return Dismissible(
                key: ValueKey(
                  'item-${item.id}-${item.updatedAt.toIso8601String()}',
                ),
                direction: dismissDirection,
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.startToEnd) {
                    if (onSwipeRight == null) {
                      return false;
                    }
                    return onSwipeRight!(item);
                  }
                  if (direction == DismissDirection.endToStart) {
                    if (onSwipeLeft == null) {
                      return false;
                    }
                    return onSwipeLeft!(item);
                  }
                  return false;
                },
                onDismissed: (_) {
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
                background: const _SwipeBackground(
                  label: 'Keep',
                  icon: Icons.favorite,
                  alignStart: true,
                  color: Colors.green,
                ),
                secondaryBackground: const _SwipeBackground(
                  label: 'Return',
                  icon: Icons.assignment_return,
                  alignStart: false,
                  color: Colors.orange,
                ),
                child: card,
              );
            },
            separatorBuilder: (context, index) => const SizedBox(height: 10),
          ),
        );
      },
    );
  }

  DismissDirection _dismissDirection() {
    final canSwipeRight = onSwipeRight != null;
    final canSwipeLeft = onSwipeLeft != null;
    if (canSwipeRight && canSwipeLeft) {
      return DismissDirection.horizontal;
    }
    if (canSwipeRight) {
      return DismissDirection.startToEnd;
    }
    if (canSwipeLeft) {
      return DismissDirection.endToStart;
    }
    return DismissDirection.none;
  }
}

class AsyncErrorState extends StatelessWidget {
  const AsyncErrorState({
    required this.message,
    required this.error,
    this.onRetry,
    super.key,
  });

  final String message;
  final Object error;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final mapped = mapToUserFacingError(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 34,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              mapped.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (mapped.actionHint != null) ...[
              const SizedBox(height: 6),
              Text(
                mapped.actionHint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => unawaited(onRetry!()),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

void _showFailureSnackBar(
  BuildContext context, {
  required Object error,
  required String fallbackPrefix,
}) {
  final mapped = mapToUserFacingError(error);
  final hintText = mapped.actionHint == null ? '' : ' ${mapped.actionHint}';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$fallbackPrefix. ${mapped.message}$hintText')),
  );
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.label,
    required this.icon,
    required this.alignStart,
    required this.color,
  });

  final String label;
  final IconData icon;
  final bool alignStart;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!alignStart) ...[
            Text(label, style: TextStyle(color: color)),
            const SizedBox(width: 8),
            Icon(icon, color: color),
          ] else ...[
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color)),
          ],
        ],
      ),
    );
  }
}

class ItemCard extends StatelessWidget {
  const ItemCard({
    required this.item,
    this.showDaysRemaining = false,
    this.onTap,
    super.key,
  });

  final ReturnItem item;
  final bool showDaysRemaining;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final daysLabel = _daysRemainingLabel(item.daysRemaining);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            item.store.label.characters.first,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(item.title),
        subtitle: Text('${item.store.label} - ${item.effectiveStatus.label}'),
        trailing: showDaysRemaining ? Text(daysLabel) : null,
        onTap: onTap,
      ),
    );
  }

  String _daysRemainingLabel(int daysRemaining) {
    if (daysRemaining < 0) {
      return '${daysRemaining.abs()}d ago';
    }
    if (daysRemaining == 0) {
      return 'Today';
    }
    return '${daysRemaining}d left';
  }
}

class ItemEditorPage extends ConsumerStatefulWidget {
  const ItemEditorPage({this.item, super.key});

  final ReturnItem? item;

  bool get isEditing => item != null;

  @override
  ConsumerState<ItemEditorPage> createState() => _ItemEditorPageState();
}

class _ItemEditorPageState extends ConsumerState<ItemEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();

  late StoreType _store;
  late ItemStatus _status;
  late DateTime _deliveredAt;
  late DateTime _returnDeadline;
  bool _isDeadlineManuallyEdited = false;

  bool _isSaving = false;
  bool _isDeleting = false;

  static const _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    final now = DateTime.now();
    _store = item?.store ?? StoreType.other;
    _status = item?.effectiveStatus ?? ItemStatus.pending;
    final initialDelivered = item?.deliveredAt ?? now;
    _deliveredAt = DeadlineEngine.atStartOfDay(initialDelivered);

    final initialWindowDays = item == null
        ? DeadlineEngine.defaultWindowForStore(_store)
        : DeadlineEngine.calculateReturnWindowDays(
            deliveredAt: _deliveredAt,
            returnDeadline: item.returnDeadline,
          );
    _returnDeadline = DeadlineEngine.calculateReturnDeadline(
      deliveredAt: _deliveredAt,
      returnWindowDays: initialWindowDays,
    );

    _titleController.text = item?.title ?? '';
    _notesController.text = item?.notes ?? '';
    _isDeadlineManuallyEdited = item != null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
  }

  int _calculateReturnWindowDays({
    required DateTime deliveredAt,
    required DateTime returnDeadline,
  }) {
    return DeadlineEngine.calculateReturnWindowDays(
      deliveredAt: deliveredAt,
      returnDeadline: returnDeadline,
    );
  }

  DateTime _maxDeadlineForDelivered(DateTime deliveredAt) {
    return DeadlineEngine.calculateReturnDeadline(
      deliveredAt: deliveredAt,
      returnWindowDays: DeadlineEngine.maxReturnWindowDays,
    );
  }

  DateTime _defaultDeadlineForStore({
    required StoreType store,
    required DateTime deliveredAt,
  }) {
    return DeadlineEngine.calculateReturnDeadline(
      deliveredAt: deliveredAt,
      returnWindowDays: DeadlineEngine.defaultWindowForStore(store),
    );
  }

  Future<void> _pickDeliveredDate() async {
    final previousDelivered = _deliveredAt;
    final currentWindowDays = _calculateReturnWindowDays(
      deliveredAt: previousDelivered,
      returnDeadline: _returnDeadline,
    );

    final picked = await showDatePicker(
      context: context,
      initialDate: _deliveredAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _deliveredAt = DeadlineEngine.atStartOfDay(picked);
      if (_isDeadlineManuallyEdited) {
        _returnDeadline = DeadlineEngine.calculateReturnDeadline(
          deliveredAt: _deliveredAt,
          returnWindowDays: currentWindowDays,
        );
      } else {
        _returnDeadline = _defaultDeadlineForStore(
          store: _store,
          deliveredAt: _deliveredAt,
        );
      }
    });
  }

  Future<void> _pickReturnDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _returnDeadline,
      firstDate: _deliveredAt,
      lastDate: _maxDeadlineForDelivered(_deliveredAt),
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _returnDeadline = DeadlineEngine.atStartOfDay(picked);
      _isDeadlineManuallyEdited = true;
    });
  }

  Future<void> _save() async {
    if (_isSaving || _isDeleting) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No authenticated user.')));
      return;
    }

    final title = _titleController.text.trim();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();
    final statusForWrite = DeadlineEngine.resolveStatus(
      status: _status,
      returnDeadline: _returnDeadline,
    );
    final repository = ref.read(itemsRepositoryProvider);

    setState(() {
      _isSaving = true;
    });

    try {
      if (widget.item == null) {
        await repository.createManualItem(
          uid: uid,
          title: title,
          store: _store,
          status: statusForWrite,
          deliveredAt: _deliveredAt,
          returnDeadline: _returnDeadline,
          notes: notes,
        );
      } else {
        final now = DateTime.now();
        final updated = widget.item!.copyWith(
          title: title,
          store: _store,
          status: statusForWrite,
          deliveredAt: _deliveredAt,
          returnDeadline: _returnDeadline,
          returnWindowDays: _calculateReturnWindowDays(
            deliveredAt: _deliveredAt,
            returnDeadline: _returnDeadline,
          ),
          normalizedTitle: title.toLowerCase(),
          notes: notes,
          updatedAt: now,
        );
        await repository.updateItem(updated);
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showFailureSnackBar(
        context,
        error: error,
        fallbackPrefix: 'Save failed',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final item = widget.item;
    if (item == null || _isSaving || _isDeleting) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete item?'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isDeleting = true;
    });

    try {
      final repository = ref.read(itemsRepositoryProvider);
      await repository.deleteItem(uid: item.uid, itemId: item.id);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showFailureSnackBar(
        context,
        error: error,
        fallbackPrefix: 'Delete failed',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isSaving || _isDeleting;
    final title = widget.isEditing ? 'Edit Item' : 'Create Item';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: isBusy ? null : _save,
            child: Text(_isSaving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _titleController,
                enabled: !isBusy,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                maxLength: 200,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Title is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<StoreType>(
                initialValue: _store,
                decoration: const InputDecoration(
                  labelText: 'Store',
                  border: OutlineInputBorder(),
                ),
                items: StoreType.values
                    .map(
                      (store) => DropdownMenuItem<StoreType>(
                        value: store,
                        child: Text(store.label),
                      ),
                    )
                    .toList(),
                onChanged: isBusy
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _store = value;
                            if (widget.item == null &&
                                !_isDeadlineManuallyEdited) {
                              _returnDeadline = _defaultDeadlineForStore(
                                store: _store,
                                deliveredAt: _deliveredAt,
                              );
                            }
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ItemStatus>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: ItemStatus.values
                    .map(
                      (status) => DropdownMenuItem<ItemStatus>(
                        value: status,
                        child: Text(status.label),
                      ),
                    )
                    .toList(),
                onChanged: isBusy
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _status = value;
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  title: const Text('Delivered Date'),
                  subtitle: Text(_formatDate(_deliveredAt)),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: isBusy ? null : _pickDeliveredDate,
                ),
              ),
              Card(
                child: ListTile(
                  title: const Text('Return Deadline'),
                  subtitle: Text(_formatDate(_returnDeadline)),
                  trailing: const Icon(Icons.event_outlined),
                  onTap: isBusy ? null : _pickReturnDeadline,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                enabled: !isBusy,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.isEditing) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: isBusy ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(_isDeleting ? 'Deleting...' : 'Delete item'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
