import 'package:flutter/material.dart';
import '../core/theme/terminal_theme.dart';
import '../data/models/category.dart';

/// Tarjeta de categoría estilo terminal: panel con borde 1px, marcador
/// cuadrado del color de la categoría y tipografía monoespaciada.
class CategoryCard extends StatelessWidget {
  const CategoryCard({super.key, required this.category, this.onTap, this.onLongPress});

  final Category category;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  Color _parseColor(String h) {
    final v = int.parse(h.replaceFirst('#', '0xFF'));
    return Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(category.color);
    return Material(
      color: TerminalTheme.panelOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: TerminalTheme.lineOf(context)),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Marcador cuadrado del color de la categoría.
              Container(
                width: 14,
                height: 14,
                color: color,
              ),
              const SizedBox(height: 12),
              Text(category.name,
                  style: TextStyle(
                      fontFamily: TerminalTheme.monoFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: TerminalTheme.fgOf(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(
                '${category.taskCount} tareas',
                style: TextStyle(
                    fontFamily: TerminalTheme.monoFamily,
                    fontSize: 12.5,
                    color: TerminalTheme.mutedOf(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
