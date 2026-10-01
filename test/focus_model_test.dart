import 'package:flutter_test/flutter_test.dart';

import 'package:slay_flutter/features/pomodoro/focus_model.dart';

void main() {
  group('FocusConfig — matemática de intervalos', () {
    test('60 min en 5 intervalos = 5 sesiones de 12 min (caso del usuario)',
        () {
      final c = const FocusConfig(
          totalMinutes: 60, intervalCount: 5, breakMinutes: 1);
      expect(c.workMinutesPerInterval, 12);
      expect(c.workSecondsPerInterval, 720);
      expect(c.breakCount, 4); // 5 intervalos → 4 descansos
      expect(c.realTotalMinutes, 64); // 60 + 4×1
      expect(c.isValid, isTrue);
    });

    test('total no divisible: el resto va al último intervalo', () {
      final c = const FocusConfig(
          totalMinutes: 62, intervalCount: 4, breakMinutes: 0);
      expect(c.workMinutesPerInterval, 15);
      // Último intervalo: 15 + resto (62 % 4 = 2) = 17.
      expect(workSecondsForIndex(c, 0), 15 * 60);
      expect(workSecondsForIndex(c, 3), 17 * 60);
    });

    test('un solo intervalo = sesión continua sin descansos', () {
      final c = const FocusConfig(
          totalMinutes: 30, intervalCount: 1, breakMinutes: 5);
      expect(c.workMinutesPerInterval, 30);
      expect(c.breakCount, 0);
      expect(c.realTotalMinutes, 30);
    });

    test('0 descansos permitido', () {
      final c = const FocusConfig(
          totalMinutes: 25, intervalCount: 2, breakMinutes: 0);
      expect(c.isValid, isTrue);
      expect(c.breakCount, 1);
      expect(c.breakSeconds, 0);
    });

    test('configs inválidas detectadas', () {
      expect(
          const FocusConfig(totalMinutes: 0, intervalCount: 1, breakMinutes: 0)
              .isValid,
          isFalse);
      expect(
          const FocusConfig(totalMinutes: 10, intervalCount: 0, breakMinutes: 0)
              .isValid,
          isFalse);
    });

    test('JSON roundtrip', () {
      const c = FocusConfig(totalMinutes: 45, intervalCount: 3, breakMinutes: 2);
      final back = FocusConfig.fromJson(c.toJson());
      expect(back.totalMinutes, 45);
      expect(back.intervalCount, 3);
      expect(back.breakMinutes, 2);
    });
  });

  group('advancePhase — transiciones', () {
    FocusRunState stateOf(FocusConfig c, FocusPhase p) => FocusRunState(
          runId: 'r',
          taskId: 't',
          taskTitle: 'T',
          config: c,
          phase: p,
          remainingSeconds: 0,
          running: true,
          startedAt: 0,
          workedSecondsTotal: 0,
        );

    test('trabajo 1 → descanso 1', () {
      final c = const FocusConfig(
          totalMinutes: 60, intervalCount: 5, breakMinutes: 2);
      final next = advancePhase(stateOf(c, const FocusWork(0)));
      expect(next, isNotNull);
      expect(next!.phase, isA<FocusBreak>());
      expect(next.phase.index, 0);
      expect(next.remainingSeconds, 120);
      expect(next.running, isTrue);
    });

    test('descanso 1 → trabajo 2', () {
      final c = const FocusConfig(
          totalMinutes: 60, intervalCount: 5, breakMinutes: 2);
      final next = advancePhase(stateOf(c, const FocusBreak(0)));
      expect(next!.phase, isA<FocusWork>());
      expect(next.phase.index, 1);
      expect(next.remainingSeconds, c.workSecondsPerInterval);
    });

    test('último trabajo → null (fin del run, wrap-up)', () {
      final c = const FocusConfig(
          totalMinutes: 60, intervalCount: 5, breakMinutes: 2);
      expect(advancePhase(stateOf(c, const FocusWork(4))), isNull);
    });

    test('ciclo completo: 3 intervalos atraviesan work-break-work-break-work',
        () {
      final c = const FocusConfig(
          totalMinutes: 30, intervalCount: 3, breakMinutes: 1);
      final kinds = <String>['work0'];
      var current = stateOf(c, const FocusWork(0));
      // Iteramos hasta que advancePhase devuelva null.
      var guard = 0;
      while (guard++ < 20) {
        final next = advancePhase(current);
        if (next == null) break;
        kinds.add(next.phase is FocusWork
            ? 'work${next.phase.index}'
            : 'break${next.phase.index}');
        current = next;
      }
      expect(kinds, ['work0', 'break0', 'work1', 'break1', 'work2']);
    });
  });

  group('FocusRunState — derivados', () {
    test('isLastWork detecta el último intervalo', () {
      final c = const FocusConfig(
          totalMinutes: 60, intervalCount: 5, breakMinutes: 1);
      final s = FocusRunState(
        runId: 'r',
        taskId: 't',
        taskTitle: 'T',
        config: c,
        phase: const FocusWork(4),
        remainingSeconds: 100,
        running: true,
        startedAt: 0,
        workedSecondsTotal: 0,
      );
      expect(s.isLastWork, isTrue);
      expect(s.currentPhaseTotalSeconds, 12 * 60);
    });

    test('phaseProgress avanza de 0 a 1', () {
      final c = const FocusConfig(
          totalMinutes: 60, intervalCount: 5, breakMinutes: 1);
      FocusRunState mk(int remaining) => FocusRunState(
            runId: 'r',
            taskId: 't',
            taskTitle: 'T',
            config: c,
            phase: const FocusWork(0),
            remainingSeconds: remaining,
            running: true,
            startedAt: 0,
            workedSecondsTotal: 0,
          );
      expect(mk(720).phaseProgress, 0.0);
      expect(mk(360).phaseProgress, closeTo(0.5, 0.001));
      expect(mk(0).phaseProgress, 1.0);
    });
  });
}
