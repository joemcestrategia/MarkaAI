/// Web helper â€” STUB for non-web platforms (Android/iOS).
/// The real implementation lives in [web_helper_real.dart].
///
/// Every function here returns a safe no-op / empty value so that the
/// code that references it compiles on mobile without pulling in dart:html.
library;

typedef MessageCallback = void Function(String data);

/// Returns the current browser origin (e.g. https://markaai.com.br).
String getWindowOrigin() => '*';

/// Listens for postMessage events from other windows.
/// Returns a cancel function.
dynamic listenPostMessage(MessageCallback cb) => null;

/// Checks the URL hash for catalog data. Returns null if none.
String? getHashCatalogData() => null;

/// Opens a URL in a new browser tab/window.
void openWindow(String url, String name) {}

/// Reads text from the browser clipboard. Returns null on mobile.
Future<String?> readClipboardWeb() async => null;

/// Registers a platform view for the bookmarklet anchor and returns true.
/// On non-web, returns false.
bool registerBookmarkletView(String viewId, String href) => false;
