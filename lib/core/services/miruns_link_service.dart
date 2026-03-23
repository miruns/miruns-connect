import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'local_db_service.dart';

/// Sync status for a capture entry on the miruns-link backend.
enum SyncStatus { none, syncing, synced, failed }

/// Thin client for the miruns-link ephemeral session sharing API.
///
/// Base URL: https://miruns-link.fly.dev
/// Web share URL: https://share.miruns.com/{code}
class MirunsLinkService {
  static const _baseUrl = 'https://miruns-link.fly.dev';
  static const shareBaseUrl = 'https://share.miruns.com';

  final LocalDbService _db;
  String? _cachedDeviceId;

  MirunsLinkService({required LocalDbService db}) : _db = db;

  /// Anonymous device ID (random, never exposes real device info).
  Future<String> _deviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    var id = await _db.getSetting('link_device_id');
    if (id == null) {
      id = _generateId();
      await _db.setSetting('link_device_id', id);
    }
    _cachedDeviceId = id;
    return id;
  }

  /// 16-char hex string — anonymous and unguessable.
  static String _generateId() {
    final rng = Random.secure();
    final bytes = List.generate(8, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Map<String, String> _headers(String deviceId) => {
    'Content-Type': 'application/json',
    'X-Device-Id': deviceId,
  };

  /// POST /sessions — returns `{ code, dataSize, expiresAt, createdAt }`.
  Future<Map<String, dynamic>> createSession(
    Map<String, dynamic> data, {
    int? ttlHours,
  }) async {
    final deviceId = await _deviceId();
    final body = <String, dynamic>{'data': data};
    if (ttlHours != null) body['ttlHours'] = ttlHours;

    final res = await http.post(
      Uri.parse('$_baseUrl/sessions'),
      headers: _headers(deviceId),
      body: jsonEncode(body),
    );
    if (res.statusCode != 201) {
      throw MirunsLinkException('Create failed (${res.statusCode})', res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// PATCH /sessions/:code — returns `{ code, dataSize, updatedAt, expiresAt }`.
  Future<Map<String, dynamic>> updateSession(
    String code,
    Map<String, dynamic> data, {
    int? ttlHours,
  }) async {
    final deviceId = await _deviceId();
    final body = <String, dynamic>{'data': data};
    if (ttlHours != null) body['ttlHours'] = ttlHours;

    final res = await http.patch(
      Uri.parse('$_baseUrl/sessions/$code'),
      headers: _headers(deviceId),
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw MirunsLinkException('Update failed (${res.statusCode})', res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// DELETE /sessions/:code — 204 on success.
  Future<void> deleteSession(String code) async {
    final deviceId = await _deviceId();
    final res = await http.delete(
      Uri.parse('$_baseUrl/sessions/$code'),
      headers: _headers(deviceId),
    );
    if (res.statusCode != 204) {
      debugPrint('[MirunsLink] Delete failed (${res.statusCode}): ${res.body}');
    }
  }

  /// Build the public share URL for a session code.
  static String shareUrl(String code) => '$shareBaseUrl/$code';
}

class MirunsLinkException implements Exception {
  final String message;
  final String? body;
  MirunsLinkException(this.message, [this.body]);

  @override
  String toString() => 'MirunsLinkException: $message';
}
