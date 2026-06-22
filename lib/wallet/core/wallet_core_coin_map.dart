export 'wallet_core_coin_map_native.dart'
    if (dart.library.js) 'wallet_core_coin_map_web.dart'
    if (dart.library.html) 'wallet_core_coin_map_web.dart'
    if (dart.library.js_util) 'wallet_core_coin_map_web.dart';
