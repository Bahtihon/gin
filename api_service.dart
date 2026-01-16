// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  // Настройка сервера
  static const String serverHost = 'www.denta1.uz';
  static const bool useHttps = true;

  static String baseUrl([String path = '']) {
    final scheme = useHttps ? 'https' : 'http';
    if (path.isEmpty) return '$scheme://$serverHost';
    if (path.startsWith('/')) path = path.substring(1);
    return '$scheme://$serverHost/$path';
  }

 /// Получить список пациентов.
/// Если [date] указана (в формате yyyy-MM-dd), вернёт пациентов за эту дату.
/// Если [date] == '' или null — вернёт всех пациентов.
static Future<List<dynamic>> fetchPatients([String? date]) async {
  final urlBase = baseUrl('api.php');
  final uri = (date != null && date.isNotEmpty)
      ? Uri.parse('$urlBase?date=$date')
      : Uri.parse(urlBase);

  final resp = await http.get(uri);
  if (resp.statusCode == 200) {
    return json.decode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
  } else {
    throw Exception('HTTP ${resp.statusCode}');
  }
}


  static Future<List<dynamic>> fetchConclusions(int patientId) async {
    final uri = Uri.parse(baseUrl('get_conclusions.php?patient_id=$patientId'));
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      return json.decode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
    }
    return [];
  }

static Future<int> fetchConclusionCount(int patientId) async {
  try {
    final uri = Uri.parse(baseUrl('get_conclusions.php?patient_id=$patientId'));
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      final data = json.decode(utf8.decode(resp.bodyBytes));
      if (data is List) return data.length;
    }
    return 0;
  } catch (_) {
    return 0;
  }
}

static Future<bool> deletePhoto(String fullName, String date, String fileName) async {
  try {
    final uri = Uri.parse(baseUrl('delete_photo.php'));
    final resp = await http.post(uri, body: {
      'fullName': fullName,
      'date': date,
      'file': fileName,
    });
    if (resp.statusCode == 200) {
      final js = json.decode(resp.body);
      return js['success'] == true;
    }
    return false;
  } catch (e) {
    debugPrint('deletePhoto error: $e');
    return false;
  }
}
// В ApiService
static Future<Map<String, dynamic>> uploadPhotoBase64({
  required String fullName,
  required String date, // format yyyy-MM-dd or 2025-11-06
  required File file,
  String? filename,
}) async {
  final bytes = await file.readAsBytes();
  final b64 = base64Encode(bytes);
  final body = json.encode({
    'fullName': fullName,
    'date': date,
    'fileName': filename ?? file.path.split(Platform.pathSeparator).last,
    'contentBase64': b64,
  });

  final uri = Uri.parse(baseUrl('upload_base64'));
  final resp = await http.post(uri, headers: {'Content-Type': 'application/json; charset=utf-8'}, body: body);
  if (resp.statusCode == 200) {
    return json.decode(resp.body) as Map<String, dynamic>;
  } else {
    throw Exception('HTTP ${resp.statusCode}');
  }
}

  static Future<Map<String, dynamic>> saveConclusion(int patientId, String text) async {
    final uri = Uri.parse(baseUrl('save_conclusion.php'));
    final resp = await http.post(uri, body: {
      'patient_id': patientId.toString(),
      'text': text,
    });
    return json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<List<String>> fetchTemplates() async {
    final uri = Uri.parse(baseUrl('get_templates.php'));
    final resp = await http.get(uri);
    if (resp.statusCode == 200) {
      final r = json.decode(utf8.decode(resp.bodyBytes));
      if (r is List) return List<String>.from(r);
    }
    return [];
  }

  static Future<List<dynamic>> fetchPhotoList(String fullName, String date) async {
    final url = baseUrl('photo_list.php') + '?fullName=${Uri.encodeComponent(fullName)}&date=$date';
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) {
      return json.decode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
    }
    return [];
  }

  // Скачивает файл (относительный путь или url) во временный файл и возвращает File
  static Future<File?> downloadFileToTemp(String remotePathOrUrl) async {
    try {
      final url = remotePathOrUrl.startsWith('http') ? remotePathOrUrl : baseUrl(remotePathOrUrl);
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) return null;
      final bytes = resp.bodyBytes;
      final dir = await getTemporaryDirectory();
      final name = DateTime.now().millisecondsSinceEpoch.toString() + '_' + (remotePathOrUrl.split('/').last);
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes);
      return f;
    } catch (e) {
      return null;
    }
  }

  // загружает изображение, привязанное к заключению
  static Future<Map<String, dynamic>> uploadConclusionImage(int patientId, int conclusionId, File file) async {
    final uri = Uri.parse(baseUrl('upload_conclusion_image.php'));
    final req = http.MultipartRequest('POST', uri);
    req.fields['patient_id'] = patientId.toString();
    req.fields['conclusion_id'] = conclusionId.toString();
    req.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    return json.decode(utf8.decode(bodyBytesFromString(body))); // helper below
  }

 
  // Вспомогатель: если body уже строка
  static List<int> bodyBytesFromString(String s) => utf8.encode(s);

  /// Добавление пациента (add_patient.php). Ожидаемые поля в body:
  /// fullName, dob (YYYY-MM-DD), phone, address, date (YYYY-MM-DD)
  static Future<Map<String, dynamic>> addPatient(Map<String, String> body) async {
    final uri = Uri.parse(baseUrl('add_patient.php'));
    final resp = await http.post(uri, body: body);
    if (resp.statusCode == 200) {
      return json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } else {
      return {'success': false, 'error': 'HTTP ${resp.statusCode}'};
    }
  }

  /// Обновление пациента (update_patient.php). Ожидаемые поля:
  /// id, fullName, dob (YYYY-MM-DD), phone, address, complaint, appointment_datetime (YYYY-MM-DD HH:MM:SS)
  static Future<Map<String, dynamic>> updatePatient(dynamic id, Map<String, String> body) async {
    final uri = Uri.parse(baseUrl('update_patient.php'));
    final payload = Map<String, String>.from(body);
    payload['id'] = id.toString();
    final resp = await http.post(uri, body: payload);
    if (resp.statusCode == 200) {
      try {
        return json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {
        return {'success': false, 'error': 'invalid json response'};
      }
    } else {
      return {'success': false, 'error': 'HTTP ${resp.statusCode}'};
    }
  }

  /// Удаление пациента (delete_patient.php). Ожидается POST id
  static Future<Map<String, dynamic>> deletePatient(dynamic id) async {
    final uri = Uri.parse(baseUrl('delete_patient.php'));
    final resp = await http.post(uri, body: {'id': id.toString()});
    if (resp.statusCode == 200) {
      try {
        return json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {
        return {'success': false, 'error': 'invalid json response'};
      }
    } else {
      return {'success': false, 'error': 'HTTP ${resp.statusCode}'};
    }
  }
 
// 1) Добавляем fetchAppointments(date) — возвращает список записей по дате
static Future<List<dynamic>> fetchAppointments([String? date]) async {
  final base = baseUrl('get_appointments.php');
  final uri = (date != null && date.isNotEmpty) ? Uri.parse('$base?date=$date') : Uri.parse(base);
  final resp = await http.get(uri);
  if (resp.statusCode == 200) {
    return json.decode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
  } else {
    throw Exception('HTTP ${resp.statusCode}');
  }
}

// 2) addAppointment (мы уже дали ранее) — пример повторяю кратко:
static Future<Map<String, dynamic>> addAppointment(Map<String, dynamic> data) async {
  final urlBase = baseUrl('add_appointment.php');
  final resp = await http.post(Uri.parse(urlBase), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: {
    'fullName': data['fullName'] ?? '',
    'dob': data['dob'] ?? '',
    'phone': data['phone'] ?? '',
    'address': data['address'] ?? '',
    'complaint': data['complaint'] ?? '',
    'appointment_datetime': data['appointment_datetime'] ?? '',
  });
  if (resp.statusCode == 200) {
     final body = utf8.decode(resp.bodyBytes).trim();

      // ⚠️ Защита: если сервер вернул не JSON, выбрасываем исключение
      if (!body.startsWith('{')) {
        throw Exception('Сервер вернул не JSON:\n$body');
      }
	
	return json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  } else {
    throw Exception('HTTP ${resp.statusCode}');
  }
}

 
  // 🔍 Поиск пациентов по всей базе
static Future<List<dynamic>> searchPatients(String query) async {
  final uri = Uri.parse(
    'https://www.denta1.uz/api.php?search=${Uri.encodeComponent(query)}',
  );
  final resp = await http.get(uri);
  if (resp.statusCode == 200) {
    return json.decode(utf8.decode(resp.bodyBytes));
  } else {
    throw Exception('Ошибка ${resp.statusCode}');
  }
 }
 
}
