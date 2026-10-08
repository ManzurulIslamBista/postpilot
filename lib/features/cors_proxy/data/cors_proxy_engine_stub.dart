import 'cors_proxy_engine.dart';

bool get isCorsProxySupported => false;

CorsProxyEngine createCorsProxyEngine() => throw UnsupportedError('A CORS proxy needs a platform that can listen on a port.');
