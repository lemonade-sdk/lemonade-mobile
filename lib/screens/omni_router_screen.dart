import 'package:flutter/material.dart';

import '../widgets/omni_router_settings.dart';

class OmniRouterScreen extends StatelessWidget {
  const OmniRouterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OmniRouter')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: OmniRouterSettings(),
      ),
    );
  }
}
