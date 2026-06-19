import 'package:flutter/material.dart';
import '../main.dart';
import 'login_page.dart';
import 'about_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? _config;
  Map<String, dynamic>? _health;
  List<dynamic> _sessions = [];
  bool _loading = true;
  bool _online = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final health = await hermesApi.getHealthDetailed();
    final config = await hermesApi.getConfig();
    final sessions = await hermesApi.getSessions();
    final online = await hermesApi.isOnline();
    setState(() {
      _health = health;
      _config = config;
      _sessions = sessions;
      _online = online;
      _loading = false;
    });
  }

  Future<void> _logout() async {
    await hermesApi.logout();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('养码猿'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStatusCard(),
                const SizedBox(height: 12),
                _buildModelCard(),
                const SizedBox(height: 12),
                _buildSessionsCard(),
              ],
            ),
          ),
    );
  }

  Widget _buildStatusCard() {
    final status = _health?['status']?.toString() ?? '未知';
    final version = _health?['version']?.toString() ?? 'N/A';
    final gatewayState = _health?['gateway_state']?.toString() ?? 'N/A';
    final activeAgents = _health?['active_agents'] ?? 0;
    final platforms = _health?['platforms'];

    // 统计已连接平台数
    int connectedPlatforms = 0;
    if (platforms is Map) {
      for (var v in platforms.values) {
        if (v is Map && v['connected'] == true) connectedPlatforms++;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, color: _online ? Colors.green : Colors.red, size: 12),
                const SizedBox(width: 8),
                Text(_online ? '在线' : '离线', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text('状态: $status'),
            Text('版本: $version'),
            Text('网关: $gatewayState'),
            Text('活跃 Agent: $activeAgents'),
            Text('已连接平台: $connectedPlatforms'),
          ],
        ),
      ),
    );
  }

  Widget _buildModelCard() {
    // 优先从最近活跃会话取实际使用的模型（capabilities 的值是启动时的静态快照）
    // sessions 列表已按 last_active 降序排列
    String modelName = 'N/A';
    String provider = 'N/A';

    if (_sessions.isNotEmpty) {
      final latest = _sessions[0];
      final m = latest['model']?.toString();
      if (m != null && m.isNotEmpty) modelName = m;
    }
    // 没有会话时回退到 capabilities 值
    if (modelName == 'N/A') {
      modelName = _config?['model']?.toString() ?? 'N/A';
    }
    // provider：优先从 capabilities 取（已改为实时读取 config）
    final p = _config?['model_provider']?.toString();
    if (p != null && p.isNotEmpty) provider = p;
    // 兜底：从 model 名的 provider/model 格式解析前缀
    if (provider == 'N/A' && modelName.contains('/')) {
      provider = modelName.split('/').first;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前模型', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('模型: $modelName'),
            Text('Provider: $provider'),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionsCard() {
    final active = _sessions.where((s) => s['ended_at'] == null).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('会话', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('活跃会话: $active'),
            Text('总会话数: ${_sessions.length}'),
          ],
        ),
      ),
    );
  }
}
