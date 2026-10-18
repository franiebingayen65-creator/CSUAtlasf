import 'package:supabase_flutter/supabase_flutter.dart';

class SchoolYearService {
  static const _key = 'active_school_year';
  static const fallback = '2025-2026';

  static Future<String> current() async {
    try {
      final r = await Supabase.instance.client
          .from('app_settings').select('value').eq('key', _key).maybeSingle();
      final v = r?['value']?.toString() ?? '';
      return v.isEmpty ? fallback : v;
    } catch (_) {
      return fallback;
    }
  }

  static String next(String sy) {
    final start = int.tryParse(sy.split('-').first) ?? 2025;
    return '${start + 1}-${start + 2}';
  }

  static String previous(String sy) {
    final start = int.tryParse(sy.split('-').first) ?? 2026;
    return '${start - 1}-$start';
  }

  static Future<void> set(String sy) => Supabase.instance.client
      .from('app_settings')
      .upsert({'key': _key, 'value': sy}, onConflict: 'key');
}