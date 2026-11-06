import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:taranaka/cores/data/database_helper.dart';
import 'package:taranaka/cores/data/table_repository.dart';
import 'package:taranaka/cores/models/cycle.dart';
import 'package:taranaka/cores/models/user.dart';
import 'package:taranaka/cores/providers/cycle_providers.dart';
import 'package:taranaka/cores/providers/language_provider.dart';
import 'package:taranaka/cores/providers/table_providers.dart';
import 'package:taranaka/cores/themes/app_theme.dart';
import 'package:taranaka/views/components/cycle_wheel.dart';
import 'package:taranaka/views/components/language_flag_button.dart';
import 'package:taranaka/views/pages/cycle_page.dart';

/// Historique en mémoire : ces tests portent sur l'écran, pas sur SQLite.
class _MemoryRepository extends TableRepository<Cycle> {
  _MemoryRepository(this.rows)
    : super(DatabaseHelper(), Cycle.table, Cycle.fromMap);

  final List<Cycle> rows;
  int _nextId = 100;

  @override
  Future<List<Cycle>> getAll({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async => [...rows];

  @override
  Future<Cycle> insert(Cycle item) async {
    final created = Cycle.fromMap({...item.toMap(), 'id': _nextId++});
    rows.add(created);
    return created;
  }

  @override
  Future<bool> update(Cycle item) async {
    final index = rows.indexWhere((c) => c.id == item.id);
    if (index < 0) return false;
    rows[index] = item;
    return true;
  }

  @override
  Future<bool> delete(int id) async {
    rows.removeWhere((c) => c.id == id);
    return true;
  }
}

class _NoUsersRepository extends TableRepository<User> {
  _NoUsersRepository() : super(DatabaseHelper(), User.table, User.fromMap);

  @override
  Future<List<User>> getAll({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async => const [];
}

Future<_MemoryRepository> _pump(
  WidgetTester tester, {
  List<Cycle> rows = const [],
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = _MemoryRepository([...rows]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cycleRepositoryProvider.overrideWithValue(repository),
        userRepositoryProvider.overrideWithValue(_NoUsersRepository()),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 2)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: const CyclePage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Finder _flag(AppLanguage language) => find.byWidgetPredicate(
  (w) => w is LanguageFlagButton && w.language == language,
);

Future<void> _saveForm(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('period-save')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('period-save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('premier cycle : date du jour en deux touches, 28 jours', (
    tester,
  ) async {
    final repository = await _pump(tester);
    expect(find.byType(CycleWheel), findsOneWidget);

    await _saveForm(tester);

    final row = repository.rows.single;
    expect(row.dateDebut, '2026-11-02');
    expect(row.dateFin, isNull);
    expect(row.intensite, isNull);
    expect(row.symptome, isNull);
    expect(row.dureCycle, isNull);
    expect(row.dureRegle, 5);
    expect(row.estimationProchain, '2026-11-30');
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('la durée connue est prise en compte au premier cycle', (
    tester,
  ) async {
    final repository = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('period-details')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('cycle-length'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '5');
    await _saveForm(tester);
    expect(repository.rows, isEmpty);

    await tester.enterText(field, '32');
    await _saveForm(tester);
    expect(repository.rows.single.dureCycle, 32);
    expect(repository.rows.single.estimationProchain, '2026-12-04');
  });

  testWidgets('une nouvelle saisie met à jour le cycle écoulé', (tester) async {
    final repository = await _pump(
      tester,
      rows: const [
        Cycle(
          id: 1,
          dateDebut: '2026-10-03',
          dureCycle: 28,
          estimationProchain: '2026-10-31',
        ),
      ],
    );
    await _saveForm(tester);

    final previous = repository.rows.firstWhere((c) => c.id == 1);
    final current = repository.rows.firstWhere((c) => c.id != 1);
    expect(previous.dureCycle, 30);
    expect(previous.estimationProchain, '2026-10-31');
    expect(current.dateDebut, '2026-11-02');
    expect(current.dureCycle, isNull);
    expect(current.estimationProchain, '2026-12-02');
  });

  testWidgets('la saisie en cours survit au défilement', (tester) async {
    await _pump(
      tester,
      size: const Size(320, 568),
      rows: const [Cycle(id: 1, dateDebut: '2026-10-05')],
    );
    final details = find.byKey(const ValueKey('period-details'));
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    await tester.tap(details);
    await tester.pumpAndSettle();
    final chip = find.byKey(const ValueKey('intensity-3'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pump();

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, 3000),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CycleWheel), findsOneWidget);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    expect(find.text('Antonony'), findsOneWidget);
  });

  testWidgets('refuse une date de début déjà enregistrée', (tester) async {
    final repository = await _pump(
      tester,
      rows: const [Cycle(id: 1, dateDebut: '2026-11-02')],
    );
    await _saveForm(tester);
    expect(repository.rows, hasLength(1));
    expect(find.text('Efa voarakitra io daty io.'), findsOneWidget);
  });

  testWidgets('signale le retard', (tester) async {
    await _pump(tester, rows: const [Cycle(id: 1, dateDebut: '2026-10-01')]);
    expect(find.text('Tara 5 andro'), findsOneWidget);
    await tester.tap(_flag(AppLanguage.fr));
    await tester.pump();
    expect(find.text('Retard de 5 jours'), findsOneWidget);
  });

  testWidgets('menu inférieur : goutte, calendrier, info', (tester) async {
    await _pump(tester);
    final bar = find.byType(NavigationBar);
    for (final icon in [
      Symbols.water_drop,
      Symbols.calendar_month,
      Symbols.info,
    ]) {
      expect(
        find.descendant(of: bar, matching: find.byIcon(icon)),
        findsOneWidget,
      );
    }
  });

  testWidgets('les trois menus suivent la langue', (tester) async {
    await _pump(
      tester,
      rows: const [
        Cycle(id: 1, dateDebut: '2026-09-07'),
        Cycle(id: 2, dateDebut: '2026-10-05'),
      ],
    );
    await tester.tap(find.text('Tetiandro'));
    await tester.pumpAndSettle();
    expect(find.text('Novambra 2026'), findsOneWidget);
    expect(find.text('28 andro'), findsOneWidget);

    await tester.tap(_flag(AppLanguage.fr));
    await tester.pumpAndSettle();
    expect(find.text('novembre 2026'), findsOneWidget);
    expect(find.text('28 jours'), findsOneWidget);

    await tester.tap(find.text('Conseils'));
    await tester.pumpAndSettle();
    expect(
      find.text('Quand consulter au Centre de Santé de Base (CSB) ?'),
      findsOneWidget,
    );
    expect(find.text('Règles qui durent plus de 7 jours.'), findsOneWidget);
  });

  testWidgets('l\'historique se corrige et se supprime', (tester) async {
    final repository = await _pump(
      tester,
      rows: const [
        Cycle(id: 1, dateDebut: '2026-09-07'),
        Cycle(id: 2, dateDebut: '2026-10-05'),
      ],
    );
    await tester.tap(find.text('Tetiandro'));
    await tester.pumpAndSettle();

    final delete = find.byKey(const ValueKey('cycle-delete-2'));
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cycle-delete-confirm')));
    await tester.pumpAndSettle();
    expect(repository.rows.map((c) => c.id), [1]);

    final edit = find.byKey(const ValueKey('cycle-edit-1'));
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('intensity-5')));
    await tester.pump();
    await _saveForm(tester);
    expect(repository.rows.single.intensite, '5');
    expect(repository.rows.single.dateDebut, '2026-09-07');
  });

  testWidgets('la date de début se choisit dans le calendrier bilingue', (
    tester,
  ) async {
    final repository = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('period-start')));
    await tester.pumpAndSettle();
    expect(find.text('Novambra 2026'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calendar-previous')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('day-2026-10-15')));
    await tester.pumpAndSettle();
    await _saveForm(tester);
    expect(repository.rows.single.dateDebut, '2026-10-15');
  });

  testWidgets('une date à venir est acceptée et annoncée sur la roue', (
    tester,
  ) async {
    final repository = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('period-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('day-2026-11-20')));
    await tester.pumpAndSettle();
    await _saveForm(tester);

    expect(repository.rows.single.dateDebut, '2026-11-20');
    expect(repository.rows.single.estimationProchain, '2026-12-18');
    expect(find.text('Hanomboka ny 20 Novambra 2026'), findsOneWidget);
  });

  testWidgets('tous les champs facultatifs arrivent en base', (tester) async {
    final repository = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('period-details')));
    await tester.pumpAndSettle();

    final end = find.byKey(const ValueKey('period-end'));
    await tester.ensureVisible(end);
    await tester.pumpAndSettle();
    await tester.tap(end);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('day-2026-11-05')));
    await tester.pumpAndSettle();

    final period = find.byKey(const ValueKey('period-length'));
    expect(tester.widget<TextField>(period).controller!.text, '4');

    Future<void> tapField(String key) async {
      final field = find.byKey(ValueKey(key));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
    }

    await tester.ensureVisible(find.byKey(const ValueKey('cycle-length')));
    await tester.enterText(find.byKey(const ValueKey('cycle-length')), '30');
    await tapField('intensity-4');
    await tapField('symptom-fatigue');
    await tester.ensureVisible(find.byKey(const ValueKey('symptom-other')));
    await tester.enterText(
      find.byKey(const ValueKey('symptom-other')),
      'Vertiges, nausées',
    );
    await _saveForm(tester);

    final row = repository.rows.single;
    expect(row.dateFin, '2026-11-05');
    expect(row.dureRegle, 4);
    expect(row.dureCycle, 30);
    expect(row.intensite, '4');
    expect(row.symptome, 'fatigue,Vertiges,nausées');
    expect(row.estimationProchain, '2026-12-02');
  });

  testWidgets('l\'intensité se retire en touchant à nouveau le niveau', (
    tester,
  ) async {
    final repository = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('period-details')));
    await tester.pumpAndSettle();
    final level = find.byKey(const ValueKey('intensity-2'));
    await tester.ensureVisible(level);
    await tester.pumpAndSettle();
    await tester.tap(level);
    await tester.pump();
    await tester.tap(level);
    await tester.pump();
    await _saveForm(tester);
    expect(repository.rows.single.intensite, isNull);
  });

  testWidgets('la correction retrouve symptômes et texte libre', (
    tester,
  ) async {
    await _pump(
      tester,
      rows: const [
        Cycle(id: 1, dateDebut: '2026-10-20', symptome: 'crampes,Vertiges'),
      ],
    );
    await tester.tap(find.text('Tetiandro'));
    await tester.pumpAndSettle();
    final edit = find.byKey(const ValueKey('cycle-edit-1'));
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();

    final chip = tester.widget<FilterChip>(
      find.byKey(const ValueKey('symptom-crampes')),
    );
    expect(chip.selected, isTrue);
    final other = find.byKey(const ValueKey('symptom-other'));
    expect(tester.widget<TextField>(other).controller!.text, 'Vertiges');
  });

  testWidgets('le calendrier marque estimationProchain', (tester) async {
    await _pump(
      tester,
      rows: const [
        Cycle(id: 1, dateDebut: '2026-10-20', estimationProchain: '2026-11-17'),
      ],
    );
    await tester.tap(find.text('Tetiandro'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('day-2026-11-17')),
        matching: find.byKey(const ValueKey('expected-flag')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('expected-flag')), findsOneWidget);
  });

  for (final (name, size, scale) in const [
    ('petit écran', Size(320, 568), 1.0),
    ('téléphone standard', Size(390, 844), 1.0),
    ('paysage', Size(844, 390), 1.0),
    ('texte agrandi x2', Size(390, 844), 2.0),
    ('petit écran, texte x2', Size(320, 568), 2.0),
  ]) {
    testWidgets('sans débordement et zones tactiles : $name', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        size: size,
        textScale: scale,
        rows: const [
          Cycle(id: 1, dateDebut: '2026-09-07', intensite: '4'),
          Cycle(id: 2, dateDebut: '2026-10-05', dateFin: '2026-10-09'),
        ],
      );
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      for (final tab in ['Tetiandro', 'Torohevitra']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      }
      handle.dispose();
    });
  }
}
