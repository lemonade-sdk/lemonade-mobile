import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../themes/app_theme_def.dart';
import '../themes/theme_registry.dart';

/// Compact dropdown selector for the active theme. Each entry shows the theme's
/// name, a short description, and a four-color swatch preview. Selecting a
/// theme hot-swaps it (no restart) and persists the choice in Isar.
class ThemePicker extends ConsumerWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(themeProvider);
    final themes = ThemeRegistry.all;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Theme', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.3)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: active.id,
              icon: Icon(Icons.expand_more, color: scheme.onSurface),
              dropdownColor: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              items: [
                for (final t in themes)
                  DropdownMenuItem<String>(
                    value: t.id,
                    child: _ThemeRow(theme: t),
                  ),
              ],
              onChanged: (id) {
                if (id == null) return;
                ref.read(themeProvider.notifier).setThemeId(id);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final AppThemeDef theme;
  const _ThemeRow({required this.theme});

  @override
  Widget build(BuildContext context) {
    final preview = theme.buildTheme().colorScheme;
    return Row(
      children: [
        _Swatch(scheme: preview),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                theme.displayName,
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                theme.description,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final ColorScheme scheme;
  const _Swatch({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 24,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(child: Container(color: scheme.surface)),
          Expanded(child: Container(color: scheme.primary)),
          Expanded(child: Container(color: scheme.secondary)),
          Expanded(child: Container(color: scheme.tertiary)),
        ],
      ),
    );
  }
}
