// Web-only implementation – compiled only for JS/Wasm targets.
// Uses dart:js_interop to call the bridge functions defined in web/index.html.
import 'dart:js_interop';

@JS('markaSubscribePush')
external JSPromise<JSString?> _markaSubscribePush(JSString vapidPublicKey);

@JS('markaUnsubscribePush')
external JSPromise<JSAny?> _markaUnsubscribePush();

Future<String?> subscribeWebPush(String vapidPublicKey) async {
  try {
    final jsResult = await _markaSubscribePush(vapidPublicKey.toJS).toDart;
    return jsResult?.toDart;
  } catch (e) {
    return null;
  }
}

Future<void> unsubscribeWebPush() async {
  try {
    await _markaUnsubscribePush().toDart;
  } catch (_) {}
}
