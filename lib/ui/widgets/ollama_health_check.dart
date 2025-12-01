import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

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
    // Check after first frame to ensure context is available for dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOllama();
    });
  }

  Future<void> _checkOllama() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:11434/'));
      if (response.statusCode == 200) {
        // Ollama is running, do nothing
        return;
      } else {
        // Ollama running but returning non-200 (unlikely for root, but possible)
        if (mounted) _showErrorDialog();
      }
    } catch (e) {
      // Connection refused or other error
      if (mounted) _showErrorDialog();
    }
  }

  Future<void> _showErrorDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Chưa tìm thấy Ollama'),
        content: const Text(
            'Ứng dụng cần Ollama để hoạt động AI Offline. Vui lòng đảm bảo Ollama đang chạy.'),
        actions: [
          TextButton(
            onPressed: () async {
              final Uri url = Uri.parse('https://ollama.com');
              if (!await launchUrl(url)) {
                // Handle error if needed, but for now just print or ignore
                debugPrint('Could not launch $url');
              }
            },
            child: const Text('Tải Ollama ngay'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              _checkOllama(); // Retry
            },
            child: const Text('Đã mở, thử lại'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
