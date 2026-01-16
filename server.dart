// lib/server.dart
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;


/// --- Корневая папка для хранения фотографий
final String photosDir = p.join(Directory.current.path, 'photos');

/// --- Запуск встроенного локального сервера
void startEmbeddedServer() async {
  final app = shelf_router.Router();

  /// --- Проверка, что сервер запущен
  app.get('/', (Request req) {
    return Response.ok(
      json.encode({'status': 'server_running'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  /// --- Получить список фото по пациенту и дате (пример: /photos/Zaycev_2025-11-06/)
  app.get('/photos/<fullName>_<date>', (Request req, String fullName, String date) async {
    final dirPath = p.join(photosDir, '${fullName}_$date');
    final dir = Directory(dirPath);

    if (!dir.existsSync()) {
      return Response.ok(json.encode([]),
          headers: {'Content-Type': 'application/json'});
    }

    final files = dir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toList();

    return Response.ok(json.encode(files),
        headers: {'Content-Type': 'application/json'});
  });

  /// --- Загрузка фото пациента
// POST /upload_base64
// Ожидает JSON:
// {
//   "fullName": "Zaycev",
//   "date": "2025-11-06",
//   "fileName": "photo1.jpg",
//   "contentBase64": "<base64 string>"
// }
app.post('/upload_base64', (Request req) async {
  try {
    final text = await req.readAsString();
    final Map js = json.decode(text);
    final String fullName = (js['fullName'] ?? '').toString();
    final String date = (js['date'] ?? '').toString();
    final String fileName = (js['fileName'] ?? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg').toString();
    final String contentBase64 = (js['contentBase64'] ?? '').toString();

    if (fullName.isEmpty || date.isEmpty || contentBase64.isEmpty) {
      return Response(400,
        body: json.encode({'success': false, 'error': 'Missing fullName/date/contentBase64'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final dirPath = p.join(photosDir, '${fullName}_$date');
    final dir = Directory(dirPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final filePath = p.join(dir.path, fileName);
    final bytes = base64Decode(contentBase64);
    final f = File(filePath);
    await f.writeAsBytes(bytes);

    return Response.ok(json.encode({'success': true, 'path': '/photos/${fullName}_$date/$fileName', 'file': fileName}),
      headers: {'Content-Type': 'application/json'});
  } catch (e, st) {
    return Response.internalServerError(
      body: json.encode({'success': false, 'error': e.toString(), 'stack': st.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
});


  /// --- Удаление фото
  app.post('/delete_photo', (Request req) async {
    try {
      final data = await req.readAsString();
      final js = json.decode(data);

      final fullName = js['fullName'] ?? '';
      final date = js['date'] ?? '';
      final file = js['file'] ?? '';

      final pathToFile = p.join(photosDir, '${fullName}_$date', file);
      final f = File(pathToFile);

      if (!f.existsSync()) {
        return Response.notFound(
          json.encode({'success': false, 'error': 'File not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await f.delete();
      return Response.ok(json.encode({'success': true}),
          headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  /// --- Отдача конкретного фото
  app.get('/photos/<fullName>_<date>/<file>', (Request req, String fullName, String date, String file) async {
    final photoPath = p.join(photosDir, '${fullName}_$date', file);
    final f = File(photoPath);

    if (!f.existsSync()) {
      return Response.notFound('File not found');
    }

    final bytes = await f.readAsBytes();
    return Response.ok(bytes, headers: {'Content-Type': 'image/jpeg'});
  });

  /// --- Запуск
  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(app);
  final server = await shelf_io.serve(handler, '0.0.0.0', 8080);
  print('✅ Local server running on port ${server.port}');
}
