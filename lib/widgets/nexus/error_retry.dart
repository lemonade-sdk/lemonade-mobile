import 'package:flutter/material.dart';

import '../../themes/nexus_tokens.dart';
import '../../utils/friendly_error.dart';
import 'nexus_ui.dart';

/// Compact reusable error body: a customer-friendly message (mapped via
/// [friendlyError]) plus a subtle Retry button.
///
/// Use inline as a section body (the default, styled like the app's error
/// cards), or set [asPage] for a centered full page/section body inside a
/// [Scaffold]/`NexusPage`.
class ErrorRetry extends StatelessWidget {
  /// The raw error. Mapped to a friendly message internally — never rendered
  /// verbatim. A pre-mapped [String] is shown as-is.
  final Object error;

  /// What failed, e.g. 'load your numbers' → "Couldn't load your numbers…".
  final String? action;

  /// Invoked by the Retry button — typically `() => ref.invalidate(provider)`.
  final VoidCallback onRetry;

  /// Render centered with breathing room, for use as a whole page body.
  final bool asPage;

  const ErrorRetry({
    super.key,
    required this.error,
    required this.onRetry,
    this.action,
    this.asPage = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    final message =
        error is String ? error as String : friendlyError(error, action: action);

    final card = NexusCard(
      radius: 15,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 16, color: t.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message,
                    style:
                        TextStyle(fontSize: 12.5, height: 1.45, color: t.text)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                    color: t.accentSoft,
                    borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.refresh, size: 13, color: t.accent2),
                  const SizedBox(width: 5),
                  Text('Retry',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.accent2)),
                ]),
              ),
            ),
          ),
        ],
      ),
    );

    if (!asPage) return card;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: card,
        ),
      ),
    );
  }
}
