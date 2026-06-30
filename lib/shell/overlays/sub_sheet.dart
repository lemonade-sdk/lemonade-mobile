import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/nav_provider.dart';
import '../../widgets/nexus/plan_picker.dart';
import 'sheet_scaffold.dart';

/// Plan + add-on picker as a bottom sheet. The picker itself lives in
/// [PlanPicker] (shared with the Plan & wallet screen); this is just the sheet
/// chrome.
class SubSheet extends ConsumerWidget {
  final String section; // 'plan' | 'billing'
  const SubSheet({super.key, required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final close = ref.read(overlayProvider.notifier).close;
    return SheetScaffold(
      onClose: close,
      child: const PlanPicker(),
    );
  }
}
