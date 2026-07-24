import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import '../../data/models/task.dart';
import '../../data/repositories/task_repository.dart';

class PomodoroScreen extends ConsumerStatefulWidget {
  const PomodoroScreen({super.key});

  @override
  ConsumerState<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends ConsumerState<PomodoroScreen> {
  static const _workDuration = 25 * 60; // 25 min
  static const _breakDuration = 5 * 60; // 5 min

  int _remaining = _workDuration;
  bool _running = false;
  bool _onBreak = false;
  Timer? _timer;
  Task? _selectedTask;

  void _toggle() {
    setState(() => _running = !_running);
    _timer?.cancel();
    if (_running) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          _remaining -= 1;
          if (_remaining <= 0) {
            _onBreak = !_onBreak;
            _remaining = _onBreak ? _breakDuration : _workDuration;
            _running = false;
            _timer?.cancel();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_onBreak ? '¡Descansa!' : '¡A trabajar!'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        });
      });
    }
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _running = false;
      _onBreak = false;
      _remaining = _workDuration;
    });
  }

  String _format(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _onBreak
        ? 1 - (_remaining / _breakDuration)
        : 1 - (_remaining / _workDuration);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pomodoro',
              style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 8),
          if (_selectedTask != null)
            Chip(
              avatar: const Icon(Icons.task_alt, size: 16),
              label: Text(_selectedTask!.title),
              onDeleted: () => setState(() => _selectedTask = null),
            ),
          const Spacer(),
          Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 240, height: 240,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 12,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _onBreak ? 'Descanso' : 'Trabajo',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(_format(_remaining),
                          style: Theme.of(context).textTheme.displayMedium),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton.filledTonal(
                iconSize: 32,
                onPressed: _reset,
                icon: const Icon(Icons.refresh),
              ),
              IconButton.filled(
                iconSize: 48,
                onPressed: _toggle,
                icon: Icon(_running ? Icons.pause : Icons.play_arrow),
              ),
              IconButton.filledTonal(
                iconSize: 32,
                onPressed: () async {
                  final tasks = await ref.read(taskRepositoryProvider).getAll();
                  if (!mounted) return;
                  final selected = await showModalBottomSheet<Task>(
                    context: context,
                    builder: (_) => ListView(
                      shrinkWrap: true,
                      children: [
                        for (final t in tasks.where((t) => !t.isCompleted))
                          ListTile(
                            title: Text(t.title),
                            onTap: () => Navigator.pop(context, t),
                          ),
                      ],
                    ),
                  );
                  if (selected != null) {
                    setState(() => _selectedTask = selected);
                  }
                },
                icon: const Icon(Icons.task_alt),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
