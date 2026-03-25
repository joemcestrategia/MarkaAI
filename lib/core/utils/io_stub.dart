/// Stub class to allow compilation on Web when referencing [File] from `dart:io`.
/// This should only be used in conjunction with conditional imports and `kIsWeb` guards.
class File {
  final String path;
  File(this.path);

  Future<bool> exists() async => false;
  Future<List<int>> readAsBytes() async => [];
  Future<String> readAsString() async => '';
  Future<File> create({bool recursive = false}) async => this;
  Future<void> writeAsBytes(List<int> bytes) async {}
  Future<void> writeAsString(String contents) async {}
}

class Directory {
  final String path;
  Directory(this.path);
  Future<bool> exists() async => false;
}

/// Stub class for Platform to avoid "Unsupported operation: Platform._operatingSystem" on Web.
class Platform {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
  static bool get isFuchsia => false;
  static String get operatingSystem => 'web';
  static Map<String, String> get environment => {};
}
