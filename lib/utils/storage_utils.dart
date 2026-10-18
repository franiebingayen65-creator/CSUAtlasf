import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class StorageUtils {
  static const bucket = 'documents';
  static const allowedExtensions = ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'];
  static SupabaseClient get _c => Supabase.instance.client;

  static String _ext(String name) {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  static String _contentType(String name) {
    switch (_ext(name)) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  static Future<String> upload(String folder, String fileName, Uint8List bytes) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await _c.storage.from(bucket).uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: _contentType(fileName)),
    );
    return path;
  }

  static String? _pathFrom(String stored) {
    if (stored.trim().isEmpty) return null;
    if (!stored.startsWith('http')) return stored;
    final marker = '/$bucket/';
    final i = stored.indexOf(marker);
    if (i < 0) return null; // external URL
    return Uri.decodeComponent(stored.substring(i + marker.length).split('?').first);
  }

  /// Display name: drops the folder and the timestamp prefix.
  static String fileName(String stored) {
    final last = stored.split('?').first.split('/').last;
    return Uri.decodeComponent(last).replaceFirst(RegExp(r'^\d+_'), '');
  }

  static Future<Uri?> signedUri(String stored, {int seconds = 3600}) async {
    final path = _pathFrom(stored);
    if (path == null) return Uri.tryParse(stored);
    final url = await _c.storage.from(bucket).createSignedUrl(path, seconds);
    return Uri.parse(url);
  }

  /// PDFs and images open in the browser. Word and ZIP files download.
  static Future<bool> open(String stored, {bool? download}) async {
    try {
      final name = fileName(stored);
      final ext = _ext(name);
      final forceDownload = download ?? (ext == 'doc' || ext == 'docx' || ext == 'zip');

      final uri = await signedUri(stored);
      if (uri == null) return false;

      final finalUri = forceDownload
          ? uri.replace(queryParameters: {...uri.queryParameters, 'download': name})
          : uri;

      return await launchUrl(finalUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('StorageUtils.open failed: $e');
      return false;
    }
  }
}

/// Calls Edge Functions that use the service-role key server-side.
class UserAdminService {
  static final _client = Supabase.instance.client;

  static Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('admin-users', body: body);
      final data = res.data;
      return data is Map ? Map<String, dynamic>.from(data) : {};
    } on FunctionException catch (e) {
      final d = e.details;
      throw Exception(d is Map && d['error'] != null ? d['error'] : 'Request failed (${e.status})');
    }
  }

  static Future<void> createUser({
    required String fullName,
    required String email,
    required String password,
    required String role,
    String? organizationId,
  }) => _call({
    'action': 'create',
    'fullName': fullName,
    'email': email,
    'password': password,
    'role': role,
    'organizationId': organizationId,
  });

  static Future<void> deleteUser(String id) =>
      _call({'action': 'delete', 'userId': id});

  static Future<void> resetPassword(String id, String password) =>
      _call({'action': 'reset_password', 'userId': id, 'password': password});

  static Future<void> updateAccount({
    required String id,
    required String fullName,
    required String email,
  }) => _call({
    'action': 'update_account',
    'userId': id,
    'fullName': fullName,
    'email': email,
  });
}