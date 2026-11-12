import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import 'stay.dart';

class StaysController extends ChangeNotifier {
  StaysController({required this.api});

  final ApiClient api;
  List<Stay> items = [];
  Stay? currentDraft;
  bool busy = false;
  String? error;

  Future<void> refresh() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final data = await api.get('/api/properties') as List<dynamic>;
      items = data
          .map((row) => Stay.fromJson(row as Map<String, dynamic>))
          .toList();
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<Stay?> createDraft({String method = 'manual'}) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final res = await api.post('/api/properties', {'setup_method': method})
          as Map<String, dynamic>;
      final stay = Stay.fromJson(res);
      currentDraft = stay;
      return stay;
    } on ApiException catch (e) {
      error = e.message;
      return null;
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
        final res = await api.post('/api/properties', stay.toPayload())
            as Map<String, dynamic>;
        currentDraft = Stay.fromJson(res);
      } else {
        final res = await api.put(
            '/api/properties/${stay.id}', stay.toPayload()) as Map<String, dynamic>;
        currentDraft = Stay.fromJson(res);
      }
      if (currentDraft != null) {
        final idx = items.indexWhere((p) => p.id == currentDraft!.id);
        if (idx >= 0) {
          items[idx] = currentDraft!;
        } else {
          items.add(currentDraft!);
        }
      }
      return true;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> publish(int id) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await api.post('/api/properties/$id/publish', {});
      await refresh();
      return true;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> uploadPhoto(int propertyId, String photoUrl,
      {bool isCover = false}) async {
    try {
      await api.post('/api/properties/$propertyId/photos', {
        'url': photoUrl,
        'is_cover': isCover,
      });
      return true;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    }
  }

  Future<void> remove(Stay stay) async {
    try {
      await api.delete('/api/properties/${stay.id}');
      items.removeWhere((item) => item.id == stay.id);
      if (currentDraft?.id == stay.id) {
        currentDraft = null;
      }
      notifyListeners();
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
    }
  }

  void clear() {
    items = [];
    currentDraft = null;
    error = null;
    notifyListeners();
  }
}

