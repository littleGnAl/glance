import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'glance_method_channel.dart';

abstract class GlancePlatform extends PlatformInterface {
  /// Constructs a GlancePlatform.
  GlancePlatform() : super(token: _token);

  static final Object _token = Object();

  static GlancePlatform _instance = MethodChannelGlance();

  /// The default instance of [GlancePlatform] to use.
  ///
  /// Defaults to [MethodChannelGlance].
  static GlancePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [GlancePlatform] when
  /// they register themselves.
  static set instance(GlancePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
