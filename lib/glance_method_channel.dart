import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'glance_platform_interface.dart';

/// An implementation of [GlancePlatform] that uses method channels.
class MethodChannelGlance extends GlancePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('glance');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
