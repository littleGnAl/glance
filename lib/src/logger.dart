/// A logger utility class.
class GlanceLogger {
  static const _tag = '[Glance]';

  /// Logs a message, this function allows logging the message in release build.
  static log(String message, {bool prefixTag = true}) {
    StringBuffer bf = StringBuffer();
    if (prefixTag) {
      bf.write(_tag);
    }
    bf.write(message);
    // We want to print the log in non-debug build
    // ignore: avoid_print
    print(bf.toString());
  }
}
