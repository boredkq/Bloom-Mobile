import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart';
import 'models.dart';

final recognitionHistoryProvider = StateNotifierProvider<
  RecognitionHistoryNotifier,
  List<RecognitionHistoryEntry>
>((ref) => RecognitionHistoryNotifier(ref.watch(jsonStoreProvider)));

class RecognitionHistoryNotifier
    extends StateNotifier<List<RecognitionHistoryEntry>> {
  RecognitionHistoryNotifier(this._store) : super(const []) {
    _load();
  }

  final JsonStore _store;
  static const String _storeKey = 'recognition_history';
  static const int _maxHistory = 50;

  void _load() {
    final raw = _store.readList(_storeKey);
    final list = <RecognitionHistoryEntry>[];
    for (final item in raw) {
      if (item is Map) {
        list.add(
          RecognitionHistoryEntry.fromJson(item.cast<String, dynamic>()),
        );
      }
    }
    state = list;
  }

  void add(RecognitionResult result) {
    final entry = RecognitionHistoryEntry(
      id: '${DateTime.now().millisecondsSinceEpoch}_${result.title}',
      result: result,
      timestamp: DateTime.now(),
    );
    final filtered =
        state.where((e) => e.result.searchPhrase != result.searchPhrase).toList();
    final updated = [entry, ...filtered];
    if (updated.length > _maxHistory) {
      state = updated.sublist(0, _maxHistory);
    } else {
      state = updated;
    }
    _persist();
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
    _persist();
  }

  void clear() {
    state = const [];
    _persist();
  }

  void _persist() {
    _store.write(_storeKey, state.map((e) => e.toJson()).toList());
  }
}
