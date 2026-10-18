import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Per-user archive state. type is 'activity' or 'report'.
class UserArchive {
  static final _db = Supabase.instance.client;
  static final ValueNotifier<int> changes = ValueNotifier(0);
  static String? _uid;
  static final Map<String, Set<String>> _cache = {};

  static Future<Set<String>> loadIds(String type) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return {};
    if (_uid != uid) {
      _cache.clear();
      _uid = uid;
    }
    final hit = _cache[type];
    if (hit != null) return hit;
    final rows = await _db.from('user_archives').select('item_id').eq('user_id', uid).eq('item_type', type);
    final set = (rows as List).map<String>((r) => r['item_id'].toString()).toSet();
    _cache[type] = set;
    return set;
  }

  /// Sets row['is_archived'] from this user's own archive list.
  static Future<List<Map<String, dynamic>>> decorate(List<Map<String, dynamic>> list, String type) async {
    final set = await loadIds(type);
    for (final m in list) {
      m['is_archived'] = m['is_archived'] == true || set.contains(m['id']?.toString());
    }
    return list;
  }

  static Future<void> setArchived(String type, Iterable<dynamic> itemIds, bool archived) async {
    final uid = _db.auth.currentUser?.id;
    final ids = itemIds.map((e) => e.toString()).toSet().toList();
    if (uid == null || ids.isEmpty) return;
    if (archived) {
      await _db.from('user_archives').upsert(
        [for (final id in ids) {'user_id': uid, 'item_type': type, 'item_id': id}],
        onConflict: 'user_id,item_type,item_id',
      );
    } else {
      await _db.from('user_archives').delete().eq('user_id', uid).eq('item_type', type).inFilter('item_id', ids);
      // also clear the shared flag set by the admin's school-year reset
      try {
        await _db
            .from(type == 'activity' ? 'activities' : 'accomplishment_reports')
            .update({'is_archived': false})
            .inFilter('id', ids);
      } catch (_) {}
    }
    final cur = await loadIds(type);
    archived ? cur.addAll(ids) : cur.removeAll(ids);
    changes.value++; // tells open screens to refresh
  }
}