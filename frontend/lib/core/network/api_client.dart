import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../storage/session_store.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;

  /// Decoded error body, e.g. `retry_after` or `missing`.
  final Map<String, dynamic>? body;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required this.session, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final SessionStore session;
  final http.Client _http;

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  Map<String, String> _headers({bool auth = true}) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth && session.token != null) {
      headers['Authorization'] = 'Bearer ${session.token}';
      if (session.activeOrgId != null) {
        headers['X-Org-Id'] = '${session.activeOrgId}';
      }
    }
    return headers;
  }

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, Map<String, dynamic> body,
      {bool auth = true}) {
    return _send('POST', path, body: body, auth: auth);
  }

  Future<dynamic> patch(String path, Map<String, dynamic> body) {
    return _send('PATCH', path, body: body);
  }

  Future<dynamic> put(String path, Map<String, dynamic> body) {
    return _send('PUT', path, body: body);
  }

  Future<void> delete(String path) async {
    await _send('DELETE', path, expectJson: false);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    bool expectJson = true,
  }) async {
    final request = http.Request(method, _uri(path))
      ..headers.addAll(_headers(auth: auth));
    if (body != null) {
      request.body = jsonEncode(body);
    }
    http.StreamedResponse streamed;
    try {
      streamed = await _http.send(request);
    } catch (_) {
      throw ApiException(
          'Cannot reach the Bleiben API at ${ApiConfig.baseUrl}');
    }
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 204 || response.body.isEmpty) {
      if (response.statusCode >= 400) {
        throw ApiException('Request failed (${response.statusCode})',
            statusCode: response.statusCode);
      }
      return null;
    }
    dynamic decoded;
    try {
      decoded = expectJson ? jsonDecode(response.body) : response.body;
    } on FormatException {
      decoded = response.body;
    }
    if (response.statusCode >= 400) {
      final map = decoded is Map<String, dynamic> ? decoded : null;
      final message = map?['detail']?.toString() ??
          'Request failed (${response.statusCode})';
      throw ApiException(message, statusCode: response.statusCode, body: map);
    }
    return decoded;
  }
}
