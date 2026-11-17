import 'razorpay_stub.dart' if (dart.library.js_interop) 'razorpay_web.dart' as impl;

/// Opens Razorpay Checkout (web). Completes with the payment fields
/// (razorpay_order_id / razorpay_payment_id / razorpay_signature), with
/// {'error': message} when the payment fails, or null if the guest closes it.
Future<Map<String, String>?> openRazorpayCheckout({
  required String keyId,
  required String orderId,
  required int amountPaise,
  required String name,
  required String description,
  String? prefillName,
  String? prefillEmail,
  String? prefillPhone,
}) =>
    impl.openRazorpayCheckout(
      keyId: keyId,
      orderId: orderId,
      amountPaise: amountPaise,
      name: name,
      description: description,
      prefillName: prefillName,
      prefillEmail: prefillEmail,
      prefillPhone: prefillPhone,
    );
