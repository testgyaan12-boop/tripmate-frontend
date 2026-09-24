import 'dart:async';
import 'dart:js_interop';

/// Razorpay web checkout bridge (Chrome/PWA), backed by the
/// `openRazorpayCheckout` function in web/index.html.
/// Call only when kIsWeb. Completes with {orderId, paymentId, signature};
/// throws on failure/dismiss.
@JS('openRazorpayCheckout')
external void _openRazorpayCheckout(
    JSObject opts, JSFunction onSuccess, JSFunction onFailure);

Future<Map<String, String>> openRazorpayWebCheckout({
  required String key,
  required int amount,
  required String currency,
  required String name,
  required String description,
  required String orderId,
  String? email,
}) {
  final done = Completer<Map<String, String>>();

  void onSuccess(String oid, String pid, String sig) {
    if (!done.isCompleted) {
      done.complete({'orderId': oid, 'paymentId': pid, 'signature': sig});
    }
  }

  void onFailure(String msg) {
    if (!done.isCompleted) done.completeError(Exception(msg));
  }

  final opts = <String, Object>{
    'key': key,
    'amount': amount,
    'currency': currency,
    'name': name,
    'description': description,
    'order_id': orderId,
    if (email != null && email.isNotEmpty) 'prefill': {'email': email},
  }.jsify() as JSObject;
  _openRazorpayCheckout(opts, onSuccess.toJS, onFailure.toJS);
  return done.future;
}
