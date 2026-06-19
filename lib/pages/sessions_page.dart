
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';

class SessionsPage extends StatefulWidget {
  final void Function(String sessionId, String? title)? onOpenSession;
  const SessionsPage({super.key, this.onOpenSession});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  List<dynamic> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _sessions = await hermesApi.getSessions();
    setState(() => _loading = false);
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '进行中';
    try {
      final ts = double.tryParse(timestamp.toString()) ?? 0;
      final dt = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
      return DateFormat('MM-dd HH:mm').format(dt);
    } catch (e) {
      return 'N/A';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('会话记录'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _sessions.isEmpty
          ? const Center(child: Text('暂无会话'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: _sessions.length,
                itemBuilder: (context, index) {
                  final s = _sessions[index];
                  final isActive = s['ended_at'] == null;
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: ListTile(
                      onTap: () {
                        final sid = s['id']?.toString() ?? s['session_id']?.toString() ?? '';
                        if (sid.isNotEmpty) {
                          widget.onOpenSession?.call(sid, s['title']?.toString());
                        }
                      },
                      leading: CircleAvatar(
                        backgroundColor: isActive ? Colors.green : Colors.grey,
                        radius: 6,
                      ),
                      title: Text(
                        s['title']?.toString() ?? '未命名会话',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${s['model'] ?? 'N/A'} · ${s['message_count'] ?? 0} 条消息 · ${_formatTime(s['started_at'])}',
                      ),
                      trailing: Text(
                        s['source']?.toString() ?? '',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
