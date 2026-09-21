import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('google.accounts.oauth2.initCodeClient')
external JSObject _initCodeClient(JSObject config);

Future<String?> getGoogleAuthCodeWeb(String clientId, String scope) async {
  final completer = Completer<String?>();

  try {
    void handleResponse(JSObject response) {
      final code = response.getProperty('code'.toJS) as JSString?;
      if (!completer.isCompleted) {
        completer.complete(code?.toDart);
      }
    }

    final config = JSObject();
    config.setProperty('client_id'.toJS, clientId.toJS);
    config.setProperty('scope'.toJS, scope.toJS);
    config.setProperty('ux_mode'.toJS, 'popup'.toJS);
    config.setProperty('prompt'.toJS, 'consent'.toJS);
    config.setProperty('callback'.toJS, handleResponse.toJS);

    final client = _initCodeClient(config);
    client.callMethod('requestCode'.toJS);

    return await completer.future;
  } catch (e) {
    if (!completer.isCompleted) completer.completeError(e);
    return null;
  }
}
