/// Preset configurable de duración del Pomodoro. Las duraciones están
/// en minutos.
///
/// Vive en `data/models/` (no en `features/pomodoro/`) porque el
/// provider que persiste la selección del user (`PomodoroSelectedPresetNotifier`
/// en `pomodoro_stats.dart`) necesita referenciarlo sin generar un
/// import circular feature → data.
class PomodoroPreset {
  const PomodoroPreset(this.label, this.work, this.shortBreak, this.longBreak,
      this.cyclesBeforeLong);
  final String label;
  final int work;
  final int shortBreak;
  final int longBreak;
  final int cyclesBeforeLong;

  bool get isCustom => label == 'Personalizado';

  static const standard =
      PomodoroPreset('Estándar', 25, 5, 15, 4);
  static const short = PomodoroPreset('Corto', 15, 3, 10, 4);
  static const long = PomodoroPreset('Largo', 50, 10, 20, 4);

  /// Sentinel de "Personalizado". Los valores reales los hidrata el
  /// overlay desde `pomodoroCustomProvider`. Usar `isCustom` para
  /// detectarlo en runtime.
  static const customSentinel = PomodoroPreset('Personalizado', 0, 0, 0, 4);

  static const builtIn = [standard, short, long];
}