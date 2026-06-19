import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dashboard_page.dart';
import 'chat_page.dart';
import 'sessions_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  final _chatKey = GlobalKey<ChatPageState>();

  void _openSession(String sessionId, String? title) {
    _chatKey.currentState?.resumeSession(sessionId, title);
    setState(() => _currentIndex = 1); // switch to chat tab
  }

  // 记录上次按返回键的时间，用于双击退出
  DateTime? _lastBackPress;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 禁止直接退出
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // 如果不在第一个标签，回到第一个标签
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return;
        }

        // 在第一个标签时：双击返回键才最小化到后台
        final now = DateTime.now();
        if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('再按一次返回键回到桌面'), duration: Duration(seconds: 2)),
          );
          return;
        }

        // 双击：最小化 App 到后台（不关闭）
        SystemNavigator.pop();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            const DashboardPage(),
            ChatPage(key: _chatKey),
            SessionsPage(onOpenSession: _openSession),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard), label: '状态'),
            NavigationDestination(icon: Icon(Icons.chat), label: '对话'),
            NavigationDestination(icon: Icon(Icons.history), label: '记录'),
          ],
        ),
      ),
    );
  }
}
