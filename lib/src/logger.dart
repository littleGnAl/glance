class GlanceLogger {
  static const _tag = '[Glance]';

  /// Log function allow us to log the message in release build.
  static log(String message, {bool prefixTag = true}) {
    StringBuffer bf = StringBuffer();
    if (prefixTag) {
      bf.write(_tag);
    }
    bf.write(message);
    // We want to print the log in release build
    // ignore: avoid_print
    print(bf.toString());
  }
}
