import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/models_provider.dart';
import '../widgets/omni_router_settings.dart';

class OmniRouterScreen extends ConsumerStatefulWidget {
  const OmniRouterScreen({super.key});

  @override
  ConsumerState<OmniRouterScreen> createState() => _OmniRouterScreenState();
}

class _OmniRouterScreenState extends ConsumerState<OmniRouterScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh installed models when the screen opens so the Installed pills
    // reflect anything installed since the last server-switch (e.g. via the
    // admin console or from another client).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(modelsProvider.notifier).fetchModels();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lemonade Omni'),
        actions: [
          IconButton(
            tooltip: 'Refresh models',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(modelsProvider.notifier).fetchModels(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(modelsProvider.notifier).fetchModels(),
        child: const SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(16),
          child: OmniRouterSettings(),
        ),
      ),
    );
  }
}
