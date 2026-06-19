import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// V1.0.1 — 基于 Hermes 内置 API Server (REST + SSE)，不依赖 hermes-web-ui
class HermesSocketService {
  String _baseUrl = '';
  String _token = '';

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;
  Stream<Map<String, dynamic>> get onStatus => _statusController.stream;
  Stream<String> get onError => _errorController.stream;

  bool get isConnected => _connected;
  bool _connected = false;
  bool _disposed = false;
  http.Client? _sseClient;
  String? _currentRunId;
  String? _currentSessionId;

  /// 当前会话 ID（只读访问）
  String? get currentSessionId => _currentSessionId;

  // BUG 4 修复：防止重复发送 run_completed / run_failed
  bool _runCompleted = false;
  bool _runFailed = false;
  bool _aborting = false;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_token',
  };

  /// BUG 7 修复：安全地向 stream 发送事件，dispose 后丢弃
  void _safeAddMessage(Map<String, dynamic> event) {
    if (_disposed || _messageController.isClosed) return;
    _messageController.add(event);
  }

  void _safeAddStatus(Map<String, dynamic> event) {
    if (_disposed || _statusController.isClosed) return;
    _statusController.add(event);
  }

  void _safeAddError(String error) {
    if (_disposed || _errorController.isClosed) return;
    _errorController.add(error);
  }

  // ═══════════════════════════════════════
  //  连接
  // ═══════════════════════════════════════

  void connect(String baseUrl, String token) {
    disconnect();
    _baseUrl = baseUrl;
    _token = token;

    // 验证连接
    _checkHealth();
  }

  Future<void> _checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (_disposed) return; // BUG 7: dispose 后不再处理

      if (response.statusCode == 200) {
        _connected = true;
        _safeAddStatus({'connected': true});
      } else {
        _connected = false;
        _safeAddStatus({'connected': false});
        _safeAddError('连接失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (_disposed) return;
      _connected = false;
      _safeAddStatus({'connected': false});
      _safeAddError('连接错误: $e');
    }
  }

  // ═══════════════════════════════════════
  //  恢复会话
  // ═══════════════════════════════════════

  void resumeSession(String sessionId) {
    _currentSessionId = sessionId;
    // 通过 REST 加载历史消息
    _loadSessionHistory(sessionId);
  }

  Future<void> _loadSessionHistory(String sessionId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/sessions/$sessionId/messages'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      if (_disposed) return; // BUG 7

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final messages = (data['data'] ?? data['messages']) as List<dynamic>? ?? [];
        if (messages.isNotEmpty) {
          _safeAddMessage({
            'type': 'resumed',
            'data': {'messages': messages},
          });
        }
      }
    } catch (e) {
      // 静默处理
    }
  }

  // ═══════════════════════════════════════
  //  发送消息
  // ═══════════════════════════════════════

  void sendMessage(String sessionId, dynamic input, {String? model, String? provider, String? profile}) {
    _currentSessionId = sessionId;

    // BUG 4: 每次新消息重置状态标志
    _runCompleted = false;
    _runFailed = false;
    _aborting = false;

    // 发送 run_started 事件
    _safeAddMessage({'type': 'run_started', 'data': {}});

    // 使用 SSE 流式接口
    _startRun(sessionId, input, profile: profile);
  }

  Future<void> _startRun(String sessionId, dynamic input, {String? profile}) async {
    try {
      final body = <String, dynamic>{
        'session_id': sessionId,
        'input': input,
        'source': 'cli',
      };
      if (profile != null) body['profile'] = profile;

      // 使用 /v1/runs 启动任务
      final response = await http.post(
        Uri.parse('$_baseUrl/v1/runs'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (_disposed) return; // BUG 7

      if (response.statusCode == 200 || response.statusCode == 202) {
        final data = jsonDecode(response.body);
        _currentRunId = data['run_id']?.toString();

        if (_currentRunId != null) {
          // 监听 SSE 事件流
          _listenRunEvents(_currentRunId!);
        } else {
          // 没有 run_id，可能是同步响应
          _handleSyncResponse(data);
        }
      } else {
        _safeAddMessage({
          'type': 'run_failed',
          'data': {'error': 'HTTP ${response.statusCode}: ${response.body}'},
        });
      }
    } catch (e) {
      if (_disposed) return;
      _safeAddMessage({
        'type': 'run_failed',
        'data': {'error': e.toString()},
      });
    }
  }

  void _handleSyncResponse(Map<String, dynamic> data) {
    // 处理同步响应（非流式）
    final output = data['output']?.toString() ?? data['content']?.toString() ?? '';
    if (output.isNotEmpty) {
      _safeAddMessage({
        'type': 'message_delta',
        'data': {'payload': {'delta': output}},
      });
    }
    _runCompleted = true;
    _safeAddMessage({'type': 'run_completed', 'data': data});
  }

  // ═══════════════════════════════════════
  //  SSE 事件流
  // ═══════════════════════════════════════

  void _listenRunEvents(String runId) {
    _sseClient?.close();

    final url = '$_baseUrl/v1/runs/$runId/events';

    final request = http.Request('GET', Uri.parse(url));
    request.headers['Authorization'] = 'Bearer $_token';
    request.headers['Accept'] = 'text/event-stream';

    _sseClient = http.Client();
    _sseClient!.send(request).then((response) {
      if (_disposed) return; // BUG 7

      if (response.statusCode != 200) {
        _safeAddMessage({
          'type': 'run_failed',
          'data': {'error': 'SSE HTTP ${response.statusCode}'},
        });
        return;
      }

      String buffer = '';
      response.stream
        .transform(utf8.decoder)
        .listen(
          (chunk) {
            if (_disposed) return; // BUG 7

            buffer += chunk;
            // 解析 SSE 事件
            final lines = buffer.split('\n');
            buffer = lines.removeLast(); // 保留不完整的行

            for (final line in lines) {
              if (line.startsWith('data: ')) {
                final jsonStr = line.substring(6).trim();
                if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;
                try {
                  final event = jsonDecode(jsonStr);
                  _handleSSEEvent(event);
                } catch (e) {
                  // SSE 解析错误静默处理
                }
              }
            }
          },
          onDone: () {
            // BUG 4 修复：只在非 abort、非 error、且未收到过 run.completed 时才发 run_completed
            if (_disposed || _aborting || _runCompleted || _runFailed) return;
            _runCompleted = true;
            _safeAddMessage({'type': 'run_completed', 'data': {}});
          },
          onError: (e) {
            if (_disposed) return;
            if (_runFailed || _runCompleted) return; // BUG 4: 已有终态，不重复
            _runFailed = true;
            _safeAddMessage({
              'type': 'run_failed',
              'data': {'error': e.toString()},
            });
          },
        );
    }).catchError((e) {
      if (_disposed) return;
      _safeAddMessage({
        'type': 'run_failed',
        'data': {'error': e.toString()},
      });
    });
  }

  void _handleSSEEvent(Map<String, dynamic> event) {
    final type = event['event']?.toString() ?? event['type']?.toString() ?? '';

    switch (type) {
      case 'message.delta':
      case 'message_delta':
      case 'response.output_text.delta':
        final delta = event['delta']?.toString() ??
            event['content']?.toString() ??
            event['text']?.toString() ?? '';
        if (delta.isNotEmpty) {
          _safeAddMessage({
            'type': 'message_delta',
            'data': {'payload': {'delta': delta}},
          });
        }
        break;

      case 'run.completed':
      case 'run_completed':
      case 'response.completed':
        // BUG 4: 标记已完成，防止 onDone 重复发送
        _runCompleted = true;
        _safeAddMessage({'type': 'run_completed', 'data': event});
        break;

      case 'run.failed':
      case 'run_failed':
      case 'response.failed':
        // BUG 4: 标记已失败，防止 onDone 重复发送
        _runFailed = true;
        final error = event['error']?.toString() ?? '未知错误';
        _safeAddMessage({
          'type': 'run_failed',
          'data': {'error': error},
        });
        break;

      case 'tool.started':
      case 'tool_started':
        final toolName = event['name']?.toString() ?? event['tool']?.toString() ?? '工具';
        _safeAddMessage({
          'type': 'tool_started',
          'data': {'name': toolName},
        });
        break;

      case 'tool.completed':
      case 'tool_completed':
        final toolName = event['name']?.toString() ?? event['tool']?.toString() ?? '工具';
        _safeAddMessage({
          'type': 'tool_completed',
          'data': {'name': toolName},
        });
        break;

      default:
        break;
    }
  }

  // ═══════════════════════════════════════
  //  停止任务
  // ═══════════════════════════════════════

  void abortSession(String sessionId) {
    // BUG 4: 标记正在 abort，阻止 onDone 发送 run_completed
    _aborting = true;
    _sseClient?.close();
    _sseClient = null;

    if (_currentRunId != null) {
      _abortRun(_currentRunId!);
    }

    // abort 时只发一次 run_completed
    if (!_runCompleted && !_runFailed) {
      _runCompleted = true;
      _safeAddMessage({'type': 'run_completed', 'data': {}});
    }
  }

  Future<void> _abortRun(String runId) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/v1/runs/$runId/stop'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      // 静默处理
    }
  }

  // ═══════════════════════════════════════
  //  断开连接
  // ═══════════════════════════════════════

  void disconnect() {
    _sseClient?.close();
    _sseClient = null;
    _connected = false;
    _currentRunId = null;
    _currentSessionId = null;
    _safeAddStatus({'connected': false});
  }

  void dispose() {
    _disposed = true;
    _sseClient?.close();
    _sseClient = null;
    _connected = false;
    _currentRunId = null;
    _currentSessionId = null;
    _messageController.close();
    _statusController.close();
    _errorController.close();
  }
}
