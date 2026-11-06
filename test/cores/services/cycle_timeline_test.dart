import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/cores/models/cycle.dart';
import 'package:taranaka/cores/services/cycle_timeline.dart';

DateTime _d(int month, int day) => DateTime.utc(2026, month, day);

Cycle _c(String start, {String? end, int? length, int? period, int? id}) =>
    Cycle(
      id: id,
      dateDebut: start,
      dateFin: end,
      dureCycle: length,
      dureRegle: period,
    );

void main() {
  group('durée moyenne', () {
    test('28 jours par défaut au premier cycle', () {
      final t = CycleTimeline([_c('2026-01-01')]);
      expect(t.averageLength, 28);
      expect(t.nextStart, _d(1, 29));
      expect(t.ovulationBefore(t.nextStart), _d(1, 15));
    });

    test('la durée déclarée remplace la valeur par défaut', () {
      final t = CycleTimeline([_c('2026-01-01', length: 32)]);
      expect(t.averageLength, 32);
    });

    test('la durée réelle remplace la durée saisie du cycle terminé', () {
      final t = CycleTimeline([_c('2026-01-01', length: 32), _c('2026-01-27')]);
      expect(t.elapsedLengths, [26]);
      expect(t.averageLength, 26);
      expect(t.predictedLength, 26);
    });

    test('la durée saisie sur le dernier cycle prime pour la prévision', () {
      final t = CycleTimeline([_c('2026-01-01'), _c('2026-01-27', length: 32)]);
      expect(t.averageLength, 26);
      expect(t.nextStart, _d(2, 28));
    });

    test('se réajuste à chaque saisie, dans n\'importe quel ordre', () {
      final t = CycleTimeline([
        _c('2026-03-01'), // 59 + ...
        _c('2026-01-01'),
        _c('2026-01-31'),
      ]);
      expect(t.elapsedLengths, [30, 29]);
      expect(t.averageLength, 30); // 29,5 arrondi
      expect(t.nextStart, _d(3, 31));
    });

    test('un cycle oublié (écart non plausible) reste hors de la moyenne', () {
      final t = CycleTimeline([
        _c('2026-01-01'),
        _c('2026-01-29'),
        _c('2026-05-01'),
      ]);
      expect(t.elapsedLengths, [28, 92]);
      expect(t.averageLength, 28);
    });

    test('ignore une ligne sans date de début', () {
      final t = CycleTimeline([const Cycle(), _c('2026-01-01')]);
      expect(t.cycles, hasLength(1));
    });
  });

  group('phases', () {
    test('cycle de 28 jours', () {
      CyclePhase at(int day) => phaseOfDay(day, 28, 5);
      expect(at(1), CyclePhase.menstruation);
      expect(at(5), CyclePhase.menstruation);
      expect(at(6), CyclePhase.follicular);
      expect(at(8), CyclePhase.follicular);
      expect(at(9), CyclePhase.ovulation);
      expect(at(14), CyclePhase.ovulation);
      expect(at(15), CyclePhase.ovulation);
      expect(at(16), CyclePhase.luteal);
      expect(at(28), CyclePhase.luteal);
    });

    test('sur un cycle court, les règles priment sur la fenêtre', () {
      expect(phaseOfDay(4, 21, 5), CyclePhase.menstruation);
      expect(phaseOfDay(6, 21, 5), CyclePhase.ovulation);
    });

    test('la date de fin saisie fixe la durée des règles', () {
      final t = CycleTimeline([_c('2026-01-01', end: '2026-01-03')]);
      final days = t.currentCycleDays(_d(1, 2));
      expect(days[2].$2, CyclePhase.menstruation);
      expect(days[3].$2, CyclePhase.follicular);
    });

    test('la durée saisie des règles prime sur la date de fin', () {
      final t = CycleTimeline([_c('2026-01-01', end: '2026-01-03', period: 7)]);
      expect(t.currentCycleDays(_d(1, 2))[6].$2, CyclePhase.menstruation);
    });

    test('5 jours de règles par défaut', () {
      final days = CycleTimeline([_c('2026-01-01')]).currentCycleDays(_d(1, 2));
      expect(days[4].$2, CyclePhase.menstruation);
      expect(days[5].$2, CyclePhase.follicular);
    });

    test('la roue a un segment par jour, à partir du début', () {
      final days = CycleTimeline([_c('2026-01-30')]).currentCycleDays(_d(2, 1));
      expect(days, hasLength(28));
      expect(days.first.$1, _d(1, 30));
      expect(days[2].$1, _d(2, 1));
    });
  });

  group('jour courant et retard', () {
    final t = CycleTimeline([_c('2026-01-01')]);

    test('compte les jours à partir de 1', () {
      expect(t.cycleDayOn(_d(1, 1)), 1);
      expect(t.cycleDayOn(_d(1, 28)), 28);
      expect(t.lateDaysOn(_d(1, 28)), 0);
    });

    test('signale le retard', () {
      expect(t.lateDaysOn(_d(1, 29)), 1);
      expect(t.lateDaysOn(_d(2, 2)), 5);
    });

    test('sans historique', () {
      final empty = CycleTimeline(const []);
      expect(empty.cycleDayOn(_d(1, 1)), isNull);
      expect(empty.lateDaysOn(_d(1, 1)), 0);
      expect(empty.nextStart, isNull);
      expect(empty.currentCycleDays(_d(1, 1)), isEmpty);
      expect(empty.markOn(_d(1, 1), _d(1, 1)), isNull);
    });
  });

  group('dates à venir', () {
    final today = _d(2, 10);

    test('un cycle uniquement à venir n\'a pas encore de jour courant', () {
      final t = CycleTimeline([_c('2026-03-01')]);
      expect(t.cycleDayOn(today), isNull);
      expect(t.upcomingStartOn(today), _d(3, 1));
      expect(t.lateDaysOn(today), 0);
      expect(t.currentCycleDays(today).first.$1, _d(3, 1));
      expect(t.markOn(today, today), isNull);
    });

    test('le cycle en cours reste celui commencé, pas le dernier saisi', () {
      final t = CycleTimeline([_c('2026-02-01'), _c('2026-03-01')]);
      expect(t.cycleDayOn(today), 10);
      expect(t.upcomingStartOn(today), isNull);
      expect(t.currentCycleDays(today).first.$1, _d(2, 1));
      expect(t.currentCycleDays(today), hasLength(28));
      expect(t.nextStartOn(today), _d(3, 1));
    });

    test('pas de retard sur un cycle suivi d\'une date saisie', () {
      final t = CycleTimeline([_c('2026-01-01'), _c('2026-03-01')]);
      expect(t.lateDaysOn(today), 0);
    });

    test('les jours à venir d\'un cycle saisi sont des prévisions', () {
      final t = CycleTimeline([_c('2026-02-01'), _c('2026-03-01')]);
      expect(t.markOn(_d(2, 20), today)!.forecast, isTrue);
      expect(t.markOn(_d(3, 2), today)!.forecast, isTrue);
      expect(t.markOn(_d(2, 2), today)!.forecast, isFalse);
    });
  });

  group('marques du calendrier', () {
    final today = _d(2, 10);
    final t = CycleTimeline([_c('2026-01-01'), _c('2026-01-31')]);

    test('rien avant le premier cycle', () {
      expect(t.markOn(DateTime.utc(2025, 12, 31), today), isNull);
    });

    test('cycle terminé : calculé sur sa durée réelle', () {
      expect(t.markOn(_d(1, 1), today), (
        phase: CyclePhase.menstruation,
        forecast: false,
      ));
      // Cycle de 30 jours : ovulation au jour 16, fenêtre du jour 11 au jour 17.
      expect(t.markOn(_d(1, 11), today)!.phase, CyclePhase.ovulation);
      expect(t.markOn(_d(1, 18), today)!.phase, CyclePhase.luteal);
    });

    test('après aujourd\'hui, tout est prévision', () {
      expect(t.markOn(_d(2, 1), today)!.forecast, isFalse);
      expect(t.markOn(_d(2, 15), today)!.forecast, isTrue);
    });

    test('projette les prochains cycles, puis s\'arrête', () {
      expect(t.markOn(_d(3, 2), today), (
        phase: CyclePhase.menstruation,
        forecast: true,
      ));
      expect(t.markOn(DateTime.utc(2026, 12, 1), today), isNull);
    });

    test('écart non plausible : seules les règles sont marquées', () {
      final gap = CycleTimeline([_c('2026-01-01'), _c('2026-05-01')]);
      expect(gap.markOn(_d(1, 2), today)!.phase, CyclePhase.menstruation);
      expect(gap.markOn(_d(2, 1), today), isNull);
    });
  });

  test('régularité', () {
    expect(
      CycleTimeline([_c('2026-01-01')]).regularity,
      CycleRegularity.unknown,
    );
    expect(
      CycleTimeline([_c('2026-01-01'), _c('2026-01-29'), _c('2026-02-28')])
          .regularity,
      CycleRegularity.regular,
    );
    expect(
      CycleTimeline([_c('2026-01-01'), _c('2026-01-23'), _c('2026-03-01')])
          .regularity,
      CycleRegularity.irregular,
    );
  });

  group('colonnes calculées', () {
    test('dure_cycle reste NULL si elle n\'est pas saisie', () {
      final rows = CycleTimeline([_c('2026-01-01', id: 1)]).outdatedRows();
      expect(rows.single.dureCycle, isNull);
      expect(rows.single.dureRegle, 5);
      expect(rows.single.estimationProchain, '2026-01-29');
    });

    test('la durée saisie du cycle sert à l\'estimation', () {
      final rows = CycleTimeline([_c('2026-01-01', id: 1, length: 32)])
          .outdatedRows();
      expect(rows.single.dureCycle, 32);
      expect(rows.single.estimationProchain, '2026-02-02');
    });

    test('dure_regle : saisie, sinon d\'après la date de fin', () {
      final rows = CycleTimeline([
        _c('2026-01-01', id: 1, end: '2026-01-04'),
        _c('2026-02-01', id: 2, end: '2026-02-04', period: 6),
      ]).outdatedRows();
      expect(rows[0].dureRegle, 4);
      expect(rows[1].dureRegle, 6);
    });

    test('le cycle terminé prend sa durée réelle et garde sa prévision', () {
      final rows = CycleTimeline([
        const Cycle(
          id: 1,
          dateDebut: '2026-01-01',
          estimationProchain: '2026-01-29',
        ),
        _c('2026-01-31', id: 2),
      ]).outdatedRows();
      expect(rows[0].dureCycle, 30);
      expect(rows[0].estimationProchain, '2026-01-29');
      expect(rows[1].dureCycle, isNull);
      expect(rows[1].estimationProchain, '2026-03-02');
    });

    test('ne réécrit plus rien une fois à jour', () {
      final first = CycleTimeline([
        _c('2026-01-01', id: 1),
        _c('2026-01-31', id: 2),
      ]).outdatedRows();
      expect(CycleTimeline(first).outdatedRows(), isEmpty);
    });
  });
}
