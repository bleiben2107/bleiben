import 'package:flutter/foundation.dart';

class ApiConfig {
  /// Override this if the API is hosted elsewhere.
  static const String overrideBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get baseUrl {
    if (overrideBaseUrl.isNotEmpty) {
      return overrideBaseUrl;
    }
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000';
      default:
        return 'http://localhost:8000';
    }
  }
}
