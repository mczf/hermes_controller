import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '8642');
  final _apiKeyController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _restoring = true;
  bool _showApiKey = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostController.text = prefs.getString('host') ?? '';
      _portController.text = prefs.getString('port') ?? '8642';
    });

    // 尝试用保存的 token 自动登录
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8642;
    if (host.isNotEmpty) {
      hermesApi.configure(host, port);
      final ok = await hermesApi.restoreSession();
      if (ok && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
        return;
      }
    }

    if (mounted) setState(() => _restoring = false);
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });

    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8642;
    final apiKey = _apiKeyController.text.trim();

    if (host.isEmpty) {
      setState(() { _error = '请输入服务器地址'; _loading = false; });
      return;
    }
    if (apiKey.isEmpty) {
      setState(() { _error = '请输入 API Key'; _loading = false; });
      return;
    }

    hermesApi.configure(host, port);
    final ok = await hermesApi.loginWithApiKey(host, port, apiKey);

    if (ok) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('host', host);
      await prefs.setString('port', port.toString());

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } else {
      setState(() { _error = '连接失败: ${hermesApi.lastError}'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在恢复登录...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hub, size: 80, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('养码猿', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('远程管控你的 AI 助手', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text('V1.0.1 — 直连 Hermes API Server', 
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 40),
              TextField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: '服务器地址 (IP 或 Tailscale IP)',
                  hintText: '192.168.x.x 或 100.x.x.x',
                  prefixIcon: Icon(Icons.dns),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: '端口',
                  hintText: '8642',
                  prefixIcon: Icon(Icons.numbers),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyController,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  hintText: 'Hermes API Server 密钥',
                  prefixIcon: const Icon(Icons.key),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_showApiKey ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showApiKey = !_showApiKey),
                  ),
                ),
                obscureText: !_showApiKey,
              ),
              const SizedBox(height: 8),
              Text(
                '在 Hermes 配置文件 ~/.hermes/config.yaml 中设置 api_server.api_key',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('连接'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }
}
