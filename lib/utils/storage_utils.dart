import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Private-bucket helpers. Store the PATH in the database, not a public URL.
/// Legacy rows that still hold public URLs are converted automatically.
class StorageUtils {
  static const bucket = 'documents';
  static SupabaseClient get _c => Supabase.instance.client;


  static Future<String> upload(String folder, String fileName, Uint8List bytes) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await _c.storage.from(bucket).uploadBinary(path, bytes);
    return path;
  }

  static String? _pathFrom(String stored) {
    if (!stored.startsWith('http')) return stored;
    final marker = '/$bucket/';
    final i = stored.indexOf(marker);
    if (i < 0) return null; // external URL
    return Uri.decodeComponent(stored.substring(i + marker.length).split('?').first);
  }

  static Future<Uri?> signedUri(String stored, {int seconds = 3600}) async {
    final path = _pathFrom(stored);
    if (path == null) return Uri.tryParse(stored);
    final url = await _c.storage.from(bucket).createSignedUrl(path, seconds);
    return Uri.parse(url);
  }

  /// Opens a stored file in the browser using a short-lived signed URL.
  static Future<bool> open(String stored) async {
    final uri = await signedUri(stored);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
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
