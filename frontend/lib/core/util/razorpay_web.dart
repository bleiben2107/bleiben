import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

@JS('Razorpay')
extension type _Razorpay._(JSObject _) implements JSObject {
  external factory _Razorpay(JSAny options);
  external void open();
  external void on(String event, JSFunction handler);
}

Future<void> _ensureScript() async {
  if (globalContext.has('Razorpay')) return;
  final done = Completer<void>();
  final script = web.HTMLScriptElement()
    ..src = 'https://checkout.razorpay.com/v1/checkout.js'
    ..async = true;
  script.onload = ((web.Event _) => done.complete()).toJS;
  script.onerror = ((web.Event _) => done.completeError('Could not load Razorpay')).toJS;
  web.document.head?.append(script);
  return done.future.timeout(const Duration(seconds: 20));
}

Map<String, String> _fields(JSAny? r) {
  final m = (r?.dartify() as Map?) ?? const {};
  return {for (final e in m.entries) '${e.key}': '${e.value}'};
}

Future<Map<String, String>?> openRazorpayCheckout({
  required String keyId,
  required String orderId,
  required int amountPaise,
  required String name,
  required String description,
  String? prefillName,
  String? prefillEmail,
  String? prefillPhone,
}) async {
  try {
    await _ensureScript();
  } catch (_) {
    return {'error': 'The payment window could not load. Check your connection and try again.'};
  }
  final result = Completer<Map<String, String>?>();
  final options = <String, Object?>{
    'key': keyId,
    'order_id': orderId,
    'amount': amountPaise,
    'currency': 'INR',
    'name': name,
    'description': description,
    'prefill': {'name': prefillName ?? '', 'email': prefillEmail ?? '', 'contact': prefillPhone ?? ''},
    'theme': {'color': '#1B4435'},
  }.jsify()! as JSObject;
  options['handler'] = ((JSAny? r) {
    if (!result.isCompleted) result.complete(_fields(r));
  }).toJS;
  options['modal'] = <String, Object?>{}.jsify();
  (options['modal']! as JSObject)['ondismiss'] = (() {
    if (!result.isCompleted) result.complete(null);
  }).toJS;
  final rz = _Razorpay(options);
  rz.on('payment.failed', ((JSAny? r) {
    final err = (r?.dartify() as Map?)?['error'] as Map?;
    if (!result.isCompleted) result.complete({'error': '${err?['description'] ?? 'Payment failed'}'});
  }).toJS);
  rz.open();
  return result.future;
}
