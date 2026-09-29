import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/terminal_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = TerminalTheme.accentOf(context);
    final muted = TerminalTheme.mutedOf(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Acerca de'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Prompt de la casa + palabra en pixel font.
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '>',
                  style: TextStyle(
                    fontFamily: TerminalTheme.pixelFamily,
                    fontSize: 34,
                    height: 1,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 5),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Container(width: 22, height: 6, color: accent),
                ),
                const SizedBox(width: 12),
                Text(
                  'Slay',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'v1.0.0',
              style: TextStyle(
                fontFamily: TerminalTheme.monoFamily,
                color: muted,
              ),
            ),
            const SizedBox(height: 24),
            Divider(color: TerminalTheme.lineOf(context), thickness: 1),
            const SizedBox(height: 16),
            const Text(
              'Aplicación de gestión de tareas diaria, construida con '
              'Flutter y respaldada por Supabase. Funciona en Android, '
              'Linux y Windows con un único código base.',
            ),
            const SizedBox(height: 16),
            Text(
              'Desarrollado por y0ner.',
              style: TextStyle(
                fontFamily: TerminalTheme.monoFamily,
                fontStyle: FontStyle.italic,
                color: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
