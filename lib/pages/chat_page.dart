import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../main.dart';
import '../services/socket_service.dart';

// ═══════════════════════════════════════
//  斜杠命令定义
// ═══════════════════════════════════════

class SlashCommand {
  final String name;
  final String description;
  const SlashCommand(this.name, this.description);
}

const List<SlashCommand> _slashCommands = [
  SlashCommand('/new', '新建会话'),
  SlashCommand('/clear', '清屏并新建会话'),
  SlashCommand('/retry', '重发上一条'),
  SlashCommand('/undo', '撤销上一轮对话'),
  SlashCommand('/title', '命名会话'),
  SlashCommand('/compress', '压缩上下文'),
  SlashCommand('/stop', '停止后台任务'),
  SlashCommand('/rollback', '回滚文件快照'),
  SlashCommand('/background', '后台运行任务'),
  SlashCommand('/queue', '排队下一轮执行'),
  SlashCommand('/resume', '恢复命名会话'),
  SlashCommand('/config', '查看配置'),
  SlashCommand('/model', '查看/切换模型'),
  SlashCommand('/personality', '设置人格'),
  SlashCommand('/reasoning', '设置推理级别'),
  SlashCommand('/verbose', '切换详细输出'),
  SlashCommand('/voice', '语音模式'),
  SlashCommand('/yolo', '跳过危险命令确认'),
  SlashCommand('/skin', '切换主题'),
  SlashCommand('/tools', '管理工具'),
  SlashCommand('/toolsets', '列出工具集'),
  SlashCommand('/skills', '搜索/安装技能'),
  SlashCommand('/skill', '加载技能到会话'),
  SlashCommand('/cron', '管理定时任务'),
  SlashCommand('/reload-mcp', '重载MCP服务'),
  SlashCommand('/plugins', '列出插件'),
  SlashCommand('/approve', '批准待审命令'),
  SlashCommand('/deny', '拒绝待审命令'),
  SlashCommand('/restart', '重启网关'),
  SlashCommand('/sethome', '设为首页频道'),
  SlashCommand('/update', '更新Hermes'),
  SlashCommand('/platforms', '查看平台状态'),
  SlashCommand('/commands', '浏览所有命令'),
  SlashCommand('/usage', 'Token用量'),
  SlashCommand('/insights', '使用分析'),
  SlashCommand('/status', '会话信息'),
  SlashCommand('/profile', '当前配置文件'),
  SlashCommand('/help', '显示帮助'),
  SlashCommand('/quit', '退出'),
];

// ═══════════════════════════════════════
//  附件数据模型
// ═══════════════════════════════════════

class Attachment {
  final String path;
  final String name;
  final int size;
  final bool isImage;
  Attachment({required this.path, required this.name, required this.size, required this.isImage});
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
  static const int _pageSize = 20;

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _socketService = HermesSocketService();

  final List<Map<String, dynamic>> _allMessages = [];
  final List<Map<String, dynamic>> _displayMessages = [];

  bool _sending = false;
  bool _connected = false;
  bool _loadingOlder = false;
  bool _hasMoreOlder = true;
  String? _currentSessionId;
  String _currentResponse = '';
  StreamSubscription? _messageSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _errorSub;

  // 附件
  final List<Attachment> _attachments = [];

  // 斜杠命令
  List<SlashCommand> _filteredCommands = [];
  bool _showCommands = false;
  // 折叠消息：记录已展开的消息内容hashCode（不用index，避免插入新消息后错位）
  final Set<int> _expandedMessages = {};

  @override
  void initState() {
    super.initState();
    _connectSocket();
    _scrollController.addListener(_onScroll);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final text = _controller.text;
    if (text.startsWith('/') && !text.contains(' ')) {
      final query = text.toLowerCase();
      setState(() {
        _filteredCommands = _slashCommands
            .where((c) => c.name.toLowerCase().startsWith(query))
            .toList();
        _showCommands = _filteredCommands.isNotEmpty;
      });
    } else {
      if (_showCommands) setState(() => _showCommands = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 50 &&
        !_loadingOlder &&
        _hasMoreOlder) {
      _loadOlderMessages();
    }
  }

  Future<void> resumeSession(String sessionId, String? title) async {
    setState(() {
      _currentSessionId = sessionId;
      _allMessages.clear();
      _displayMessages.clear();
      _currentResponse = '';
      _sending = false;
      _hasMoreOlder = true;
    });

    // 通过 socket service 加载历史消息（调用 /api/sessions/{id}/messages）
    _socketService.resumeSession(sessionId);
  }

  void _loadOlderMessages() {
    if (_loadingOlder || !_hasMoreOlder) return;
    setState(() => _loadingOlder = true);

    final allLen = _allMessages.length;
    final dispLen = _displayMessages.length;
    if (dispLen >= allLen) {
      setState(() { _loadingOlder = false; _hasMoreOlder = false; });
      return;
    }

    final olderCount = allLen - dispLen;
    final loadCount = olderCount > _pageSize ? _pageSize : olderCount;
    final startIdx = olderCount - loadCount;
    final older = _allMessages.sublist(startIdx, startIdx + loadCount);

    final prevExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    setState(() {
      _displayMessages.addAll(older.reversed);
      _loadingOlder = false;
      if (startIdx == 0) _hasMoreOlder = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final newExtent = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(_scrollController.position.pixels + (newExtent - prevExtent));
      }
    });
  }

  void _connectSocket() {
    _messageSub?.cancel();
    _statusSub?.cancel();
    _errorSub?.cancel();
    _socketService.disconnect();

    _socketService.connect(hermesApi.baseUrl, hermesApi.token);

    _messageSub = _socketService.onMessage.listen((event) {
      final type = event['type'];
      var rawData = event['data'];
      final data = (rawData is List && rawData.isNotEmpty) ? rawData[0] : rawData;

      switch (type) {
        case 'run_started':
          setState(() { _sending = true; _currentResponse = ''; });
          break;

        case 'message_delta':
          final delta = data['payload']?['delta'] ?? data['delta'] ?? '';
          if (delta is String && delta.isNotEmpty) {
            setState(() {
              _currentResponse += delta;
              if (_displayMessages.isNotEmpty && _displayMessages[0]['role'] == 'assistant') {
                _displayMessages[0]['content'] = _currentResponse;
              } else {
                final msg = {'role': 'assistant', 'content': _currentResponse};
                _allMessages.add(msg);
                _displayMessages.insert(0, msg);
              }
            });
          }
          break;

        case 'run_completed':
          setState(() {
            _sending = false;
            if (_currentResponse.isNotEmpty) {
              if (_displayMessages.isNotEmpty && _displayMessages[0]['role'] == 'assistant') {
                _displayMessages[0]['content'] = _currentResponse;
              }
            }
            _currentResponse = '';
          });
          break;

        case 'run_failed':
          setState(() {
            _sending = false;
            final error = data['error']?.toString() ?? '未知错误';
            final msg = {'role': 'error', 'content': '⚠️ $error'};
            _allMessages.add(msg);
            _displayMessages.insert(0, msg);
            _currentResponse = '';
          });
          break;

        case 'resumed':
          final messages = data['messages'] as List<dynamic>? ?? [];
          if (messages.isNotEmpty && _allMessages.isEmpty) {
            final msgs = <Map<String, dynamic>>[];
            for (var msg in messages) {
              msgs.add({
                'role': msg['role']?.toString() ?? 'unknown',
                'content': msg['content']?.toString() ?? '',
              });
            }
            setState(() {
              _allMessages.addAll(msgs);
              _displayMessages.clear();
              final start = msgs.length > _pageSize ? msgs.length - _pageSize : 0;
              _displayMessages.addAll(msgs.sublist(start).reversed);
              if (start == 0) _hasMoreOlder = false;
            });
          }
          break;

        case 'tool_started':
          final toolName = data['payload']?['name'] ?? data['name'] ?? '工具';
          setState(() {
            final msg = {'role': 'tool', 'content': '🔧 使用工具: $toolName...'};
            _allMessages.add(msg);
            _displayMessages.insert(0, msg);
          });
          break;

        case 'tool_completed':
          final toolName = data['payload']?['name'] ?? data['name'] ?? '工具';
          setState(() {
            final msg = {'role': 'tool', 'content': '✅ 工具完成: $toolName'};
            _allMessages.add(msg);
            _displayMessages.insert(0, msg);
          });
          break;
      }
    });

    _statusSub = _socketService.onStatus.listen((status) {
      setState(() { _connected = status['connected'] ?? false; });
    });

    _errorSub = _socketService.onError.listen((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    });
  }

  // ═══════════════════════════════════════
  //  发送 / 停止
  // ═══════════════════════════════════════

  Future<void> _send() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _attachments.isEmpty) || _sending) return;

    _currentSessionId ??= 'mobile_${DateTime.now().millisecondsSinceEpoch}';

    // 构建显示内容（文本 + 附件信息）
    String displayContent = text;
    if (_attachments.isNotEmpty) {
      final attachNames = _attachments.map((a) => '📎 ${a.name}').join('\n');
      displayContent = text.isEmpty ? attachNames : '$text\n$attachNames';
    }

    setState(() {
      final msg = {'role': 'user', 'content': displayContent};
      _allMessages.add(msg);
      _displayMessages.insert(0, msg);
      _sending = true;
      _showCommands = false;
    });
    _controller.clear();

    final imageAttachments = _attachments.where((a) => a.isImage).toList();
    final nonImageAttachments = _attachments.where((a) => !a.isImage).toList();

    if (imageAttachments.isNotEmpty) {
      // 有图片附件：构建 OpenAI 多模态内容发送
      final contentParts = <Map<String, dynamic>>[];

      // 文本部分（包括非图片附件的文件名）
      String textPart = text;
      if (nonImageAttachments.isNotEmpty) {
        final names = nonImageAttachments.map((a) => a.name).join(', ');
        textPart = text.isEmpty ? '[附件: $names]' : '$text\n[附件: $names]';
      }
      if (textPart.isNotEmpty) {
        contentParts.add({'type': 'text', 'text': textPart});
      }

      // 图片部分：读取文件转 base64 data URL
      for (final img in imageAttachments) {
        try {
          final bytes = await File(img.path).readAsBytes();
          final base64Str = base64Encode(bytes);
          final ext = p.extension(img.path).toLowerCase().replaceAll('.', '');
          final mimeType = ext == 'jpg' ? 'jpeg' : (ext.isEmpty ? 'jpeg' : ext);
          contentParts.add({
            'type': 'image_url',
            'image_url': {'url': 'data:image/$mimeType;base64,$base64Str'},
          });
        } catch (e) {
          // 读取失败，在文本中注明
          if (contentParts.isNotEmpty && contentParts.last['type'] == 'text') {
            contentParts.last['text'] += '\n[图片读取失败: ${img.name}]';
          } else {
            contentParts.add({'type': 'text', 'text': '[图片读取失败: ${img.name}]'});
          }
        }
      }

      // 以多模态格式发送：input = [{"role":"user","content":[...]}]
      _socketService.sendMessage(
        _currentSessionId!,
        [{'role': 'user', 'content': contentParts}],
        profile: 'default',
      );
    } else {
      // 无图片：纯文本发送
      String sendInput = text;
      if (nonImageAttachments.isNotEmpty) {
        final attachNames = nonImageAttachments.map((a) => a.name).join(', ');
        sendInput = text.isEmpty ? '[附件: $attachNames]' : '$text\n[附件: $attachNames]';
      }
      _socketService.sendMessage(
        _currentSessionId!,
        sendInput,
        profile: 'default',
      );
    }

    setState(() => _attachments.clear());
  }

  void _stop() {
    if (_currentSessionId != null) {
      _socketService.abortSession(_currentSessionId!);
    }
    setState(() {
      _sending = false;
      _currentResponse = '';
    });
  }

  void _newSession() {
    setState(() {
      _allMessages.clear();
      _displayMessages.clear();
      _currentSessionId = null;
      _currentResponse = '';
      _hasMoreOlder = true;
      _attachments.clear();
      _showCommands = false;
    });
  }

  // ═══════════════════════════════════════
  //  附件选择
  // ═══════════════════════════════════════

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          for (final file in result.files) {
            if (file.path != null) {
              final ext = p.extension(file.name).toLowerCase();
              final isImage = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].contains(ext);
              _attachments.add(Attachment(
                path: file.path!,
                name: file.name,
                size: file.size,
                isImage: isImage,
              ));
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择文件失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  // ═══════════════════════════════════════
  //  构建UI
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('与 Hermes 对话'),
            Text(
              _connected ? '已连接' : '未连接',
              style: TextStyle(
                fontSize: 12,
                color: _connected ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _newSession,
            tooltip: '新会话',
          ),
          IconButton(
            icon: Icon(_connected ? Icons.link : Icons.link_off),
            onPressed: () {
              if (_connected) {
                _socketService.disconnect();
              } else {
                _connectSocket();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: _displayMessages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64,
                        color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(_connected
                        ? '发送消息开始对话'
                        : '正在连接...',
                        style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: _displayMessages.length + (_hasMoreOlder ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_hasMoreOlder && index == _displayMessages.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: _loadingOlder
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : TextButton(
                                onPressed: _loadOlderMessages,
                                child: const Text('加载更早消息'),
                              ),
                        ),
                      );
                    }

                    final msg = _displayMessages[index];
                    final role = msg['role']?.toString() ?? 'unknown';
                    final content = msg['content']?.toString() ?? '';
                    final isUser = role == 'user';
                    final isAssistant = role == 'assistant';
                    final isTool = role == 'tool';
                    final isError = role == 'error';

                    // 判断是否为需要折叠的消息（工具输出、错误、JSON终端输出）
                    final isTerminalOutput = isError || isTool ||
                        (content.contains('"output"') && content.contains('"exit_code"')) ||
                        (content.contains('"error"') && content.contains('"exit_code"'));
                    final msgHash = content.hashCode;
                    final isExpanded = _expandedMessages.contains(msgHash);
                    final displayContent = (isTerminalOutput && !isExpanded)
                        ? content.split('\n').first
                        : content;
                    final hasMoreLines = content.contains('\n');

                    Color bgColor;
                    Color textColor;
                    IconData icon;
                    Alignment alignment;

                    if (isUser) {
                      bgColor = Theme.of(context).colorScheme.primaryContainer;
                      textColor = Theme.of(context).colorScheme.onPrimaryContainer;
                      icon = Icons.person;
                      alignment = Alignment.centerRight;
                    } else if (isAssistant) {
                      bgColor = Theme.of(context).colorScheme.surfaceContainerHighest;
                      textColor = Theme.of(context).colorScheme.onSurface;
                      icon = Icons.smart_toy;
                      alignment = Alignment.centerLeft;
                    } else if (isTool) {
                      bgColor = Theme.of(context).colorScheme.tertiaryContainer;
                      textColor = Theme.of(context).colorScheme.onTertiaryContainer;
                      icon = Icons.build;
                      alignment = Alignment.centerLeft;
                    } else if (isError) {
                      bgColor = Theme.of(context).colorScheme.errorContainer;
                      textColor = Theme.of(context).colorScheme.onErrorContainer;
                      icon = Icons.error;
                      alignment = Alignment.centerLeft;
                    } else {
                      bgColor = Theme.of(context).colorScheme.surfaceContainerHighest;
                      textColor = Theme.of(context).colorScheme.onSurface;
                      icon = Icons.info;
                      alignment = Alignment.centerLeft;
                    }

                    return Align(
                      alignment: alignment,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.85,
                        ),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isUser) ...[
                              Icon(icon, size: 16, color: textColor),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: GestureDetector(
                                onTap: isTerminalOutput && hasMoreLines
                                    ? () => setState(() {
                                        if (isExpanded) {
                                          _expandedMessages.remove(msgHash);
                                        } else {
                                          _expandedMessages.add(msgHash);
                                        }
                                      })
                                    : null,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SelectableText(
                                      displayContent,
                                      style: TextStyle(color: textColor),
                                      maxLines: isTerminalOutput && !isExpanded ? 1 : null,
                                    ),
                                    if (isTerminalOutput && hasMoreLines)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          isExpanded ? '▲ 收起' : '▼ 展开全部',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: textColor.withValues(alpha: 0.6),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (isUser) ...[
                              const SizedBox(width: 8),
                              Icon(icon, size: 16, color: textColor),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),

          // 思考中指示器
          if (_sending && _currentResponse.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Hermes 正在思考...'),
                ],
              ),
            ),

          // 斜杠命令提示
          if (_showCommands)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredCommands.length,
                itemBuilder: (context, index) {
                  final cmd = _filteredCommands[index];
                  return ListTile(
                    dense: true,
                    title: Text(cmd.name, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                    subtitle: Text(cmd.description, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
                    onTap: () {
                      _controller.text = '${cmd.name} ';
                      _controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: _controller.text.length),
                      );
                      setState(() => _showCommands = false);
                      _focusNode.requestFocus();
                    },
                  );
                },
              ),
            ),

          // 附件预览
          if (_attachments.isNotEmpty)
            Container(
              height: 80,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _attachments.length,
                itemBuilder: (context, index) {
                  final att = _attachments[index];
                  return Container(
                    width: 120,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                att.isImage ? Icons.image : Icons.attach_file,
                                size: 24,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                att.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                _formatSize(att.size),
                                style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.outline),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => _removeAttachment(index),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.close, size: 14, color: Theme.of(context).colorScheme.onError),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          // 输入区域
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black12)],
            ),
            child: Row(
              children: [
                // 附件按钮
                IconButton(
                  onPressed: _sending ? null : _pickFiles,
                  icon: const Icon(Icons.attach_file),
                  tooltip: '添加附件',
                ),
                // 输入框
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: _connected ? '输入消息或 / 命令...' : '连接中...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    enabled: _connected,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                // 发送 / 停止按钮
                if (_sending)
                  IconButton.filled(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    tooltip: '停止',
                  )
                else
                  IconButton.filled(
                    onPressed: !_connected ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _messageSub?.cancel();
    _statusSub?.cancel();
    _errorSub?.cancel();
    _socketService.dispose();
    super.dispose();
  }
}
