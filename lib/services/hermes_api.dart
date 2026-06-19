import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// V1.0.1 — 使用 Hermes 内置 API Server，不依赖 hermes-web-ui
class HermesApi {
  String _baseUrl = '';
  String _token = '';
  String lastError = '';

  String get baseUrl => _baseUrl;
  String get token => _token;
  bool get isLoggedIn => _token.isNotEmpty;

  void configure(String host, int port) {
    _baseUrl = 'http://$host:$port';
  }

  /// 从本地存储恢复登录状态，返回是否有效
  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('host') ?? '';
    final port = prefs.getString('port') ?? '8642';
    final token = prefs.getString('token') ?? '';

    if (host.isEmpty || token.isEmpty) return false;

    _baseUrl = 'http://$host:$port';
    _token = token;

    // 验证 token 是否仍然有效
    final ok = await testConnection();
    if (ok) return true;

    // token 失效，清除
    _token = '';
    await prefs.remove('token');
    return false;
  }

  /// V1.0.1: 使用 API Key 登录（Hermes API Server 方式）
  Future<bool> loginWithApiKey(String host, int port, String apiKey) async {
    try {
      _baseUrl = 'http://$host:$port';
      _token = apiKey;

      // 验证连接
      final ok = await testConnection();
      if (ok) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('host', host);
        await prefs.setString('port', port.toString());
        await prefs.setString('token', apiKey);
        return true;
      }

      lastError = '无法连接到 Hermes API Server';
      _token = '';
      return false;
    } catch (e) {
      lastError = e.toString();
      _token = '';
      return false;
    }
  }

  Future<void> logout() async {
    _token = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_token',
  };

  /// 获取网关健康状态（/health/detailed 返回网关状态，无用户信息）
  Future<Map<String, dynamic>?> getHealthDetailed() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/health/detailed'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 简单健康检查，判断网关是否在线
  Future<bool> isOnline() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getConfig() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/v1/capabilities'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<dynamic>> getSessions() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/sessions'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getSession(String sessionId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/sessions/$sessionId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 获取会话消息列表
  Future<List<dynamic>> getSessionMessages(String sessionId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/sessions/$sessionId/messages'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
