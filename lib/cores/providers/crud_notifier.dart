import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/table_repository.dart';
import '../models/model.dart';

/// Change à chaque suppression. Toutes les listes en dépendent, car une
/// suppression peut en modifier d'autres via `ON DELETE CASCADE` / `SET NULL`.
final _deletionsProvider = Provider<Object>((ref) => Object());

/// Expose le contenu d'une table et ses opérations CRUD.
///
/// Les erreurs d'écriture (contrainte violée par exemple) remontent à
/// l'appelant et laissent la liste affichée intacte.
class CrudNotifier<T extends Model> extends AsyncNotifier<List<T>> {
  CrudNotifier(this._repositoryProvider);

  final Provider<TableRepository<T>> _repositoryProvider;

  TableRepository<T> get _repository => ref.read(_repositoryProvider);

  @override
  Future<List<T>> build() {
    ref.watch(_deletionsProvider);
    return ref.watch(_repositoryProvider).getAll();
  }

  Future<T> add(T item) async {
    final created = await _repository.insert(item);
    await _reload();
    return created;
  }

  Future<bool> edit(T item) async {
    final updated = await _repository.update(item);
    await _reload();
    return updated;
  }

  Future<bool> remove(int id) async {
    final removed = await _repository.delete(id);
    ref.invalidate(_deletionsProvider);
    await future;
    return removed;
  }

  Future<void> _reload() {
    ref.invalidateSelf();
    return future;
  }
}
