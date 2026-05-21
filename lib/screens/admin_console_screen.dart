import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/lemonade_client_provider.dart';
import '../widgets/admin/admin_backends_tab.dart';
import '../widgets/admin/admin_dashboard_tab.dart';
import '../widgets/admin/admin_logs_tab.dart';
import '../widgets/admin/admin_models_tab.dart';
import '../widgets/admin/admin_system_info_tab.dart';

/// Five-tab console for managing the connected Lemonade server.
class AdminConsoleScreen extends ConsumerWidget {
  const AdminConsoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(lemonadeClientProvider);

    if (client == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Select a server first to access admin features.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Admin · ${client.server.name}'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Dashboard', icon: Icon(Icons.dashboard)),
              Tab(text: 'Models', icon: Icon(Icons.model_training)),
              Tab(text: 'Backends', icon: Icon(Icons.developer_board)),
              Tab(text: 'System', icon: Icon(Icons.computer)),
              Tab(text: 'Logs', icon: Icon(Icons.receipt_long)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminDashboardTab(),
            AdminModelsTab(),
            AdminBackendsTab(),
            AdminSystemInfoTab(),
            AdminLogsTab(),
          ],
        ),
      ),
    );
  }
}
