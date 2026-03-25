/// Stub for Web-only dart:html to allow mobile compilation.
class WindowStub {
  HistoryStub get history => HistoryStub();
}

class HistoryStub {
  void replaceState(dynamic data, String title, String? url) {}
}

class DocumentStub {
  String title = '';
}

final window = WindowStub();
final document = DocumentStub();
