import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cycle.dart';
import '../services/cycle_timeline.dart';
import 'table_providers.dart';

/// Horloge remplaçable dans les tests. C'est une fonction pour que la date reste
/// juste si l'application reste ouverte au-delà de minuit.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final cycleTimelineProvider = Provider<AsyncValue<CycleTimeline>>(
  (ref) => ref.watch(cyclesProvider).whenData(CycleTimeline.new),
);

final cycleJournalProvider = Provider<CycleJournal>(CycleJournal.new);

/// Écritures dans l'historique. La ligne saisie part complète (une création
/// reste donc en `version = 1`), puis ses voisines sont recalculées. Si ce
/// recalcul est interrompu, l'écriture suivante le rattrape.
class CycleJournal {
  CycleJournal(this._ref);

  final Ref _ref;

  Future<void> save(Cycle cycle) async {
    final notifier = _ref.read(cyclesProvider.notifier);
    final before = CycleTimeline(await _ref.read(cyclesProvider.future));

    final owned = cycle.withUser(cycle.userId ?? await _localUserId());
    final merged = CycleTimeline([
      ...before.cycles.where((c) => c.id != owned.id),
      owned,
    ]);
    final row = merged.computed(owned);

    if (row.id == null) {
      await notifier.add(row);
    } else {
      await notifier.edit(row);
    }
    await _refreshComputedValues(before);
  }

  Future<void> remove(int id) async {
    final before = CycleTimeline(await _ref.read(cyclesProvider.future));
    await _ref.read(cyclesProvider.notifier).remove(id);
    await _refreshComputedValues(before);
  }

  /// Tant que l'application n'a pas de session, l'utilisatrice est le premier
  /// compte local. Sans compte, `User_id` reste `NULL`.
  Future<int?> _localUserId() async {
    final users = await _ref.read(userRepositoryProvider).getAll(orderBy: 'id');
    return users.isEmpty ? null : users.first.id;
  }

  Future<void> _refreshComputedValues(CycleTimeline before) async {
    final notifier = _ref.read(cyclesProvider.notifier);
    var timeline = CycleTimeline(await _ref.read(cyclesProvider.future));

    // Un cycle redevenu le dernier porte une durée mesurée jusqu'à un suivant
    // qui n'existe plus : ce n'est pas une valeur saisie.
    final last = timeline.isEmpty ? null : timeline.cycles.last;
    final previousLastId = before.isEmpty ? null : before.cycles.last.id;
    if (last != null &&
        last.id != previousLastId &&
        before.cycles.any((c) => c.id == last.id)) {
      await notifier.edit(
        last.withComputed(
          dureCycle: null,
          dureRegle: last.dureRegle,
          estimationProchain: last.estimationProchain,
        ),
      );
      timeline = CycleTimeline(await _ref.read(cyclesProvider.future));
    }

    for (final row in timeline.outdatedRows()) {
      await notifier.edit(row);
    }
  }
}
