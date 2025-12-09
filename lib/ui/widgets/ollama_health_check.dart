import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/config_provider.dart';

/// Stealth Mode: Silently checks AI provider health on startup
/// Updates ConfigProvider state instead of showing intrusive dialogs
class OllamaHealthCheck extends StatefulWidget {
  final Widget child;

  const OllamaHealthCheck({super.key, required this.child});

  @override
  State<OllamaHealthCheck> createState() => _OllamaHealthCheckState();
}

class _OllamaHealthCheckState extends State<OllamaHealthCheck> {
  @override
  void initState() {
    super.initState();
    // Check after first frame to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOllama();
    });
  }

  Future<void> _checkOllama() async {
    if (!mounted) return;
    // Stealth Mode: Update ConfigProvider state silently (no dialogs)
    await context.read<ConfigProvider>().checkOllamaHealth();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
