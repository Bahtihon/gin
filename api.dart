// lib/services/api.dart
const String serverHost = 'www.denta1.uz';
const bool useHttps = true;

String baseUrl([String path = '']) =>
    '${useHttps ? 'https' : 'http'}://$serverHost${path.isNotEmpty ? '/$path' : ''}';
