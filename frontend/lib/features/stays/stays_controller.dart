import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import 'stay.dart';

class StaysController extends ChangeNotifier {
  StaysController({required this.api});

  final ApiClient api;
  List<Stay> items = [];
  bool busy = false;
  String? error;

  Future<void> refresh() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final data = await api.get('/api/stays') as List<dynamic>;
      items = data.map((row) => Stay.fromJson(row as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> save(Stay stay) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (stay.id == 0) {
        await api.post('/api/stays', stay.toPayload());
      } else {
        await api.patch('/api/stays/${stay.id}', stay.toPayload());
      }
      await refresh();
      return true;
    } on ApiException catch (e) {
      error = e.message;
      busy = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> remove(Stay stay) async {
    await api.delete('/api/stays/${stay.id}');
    items.removeWhere((item) => item.id == stay.id);
    notifyListeners();
  }

  void clear() {
    items = [];
    error = null;
    notifyListeners();
  }
}
