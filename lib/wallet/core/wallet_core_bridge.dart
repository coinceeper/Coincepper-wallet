export 'wallet_core_bridge_native.dart'
    if (dart.library.js) 'wallet_core_bridge_web.dart'
    if (dart.library.html) 'wallet_core_bridge_web.dart'
    if (dart.library.js_util) 'wallet_core_bridge_web.dart';
