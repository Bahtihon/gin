// lib/services/photo_service.dart
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'settings_service.dart';

class PhotoService {
  final _picker = ImagePicker();
  final _settings = SettingsService();

  Future<void> takeAndUpload(String patientId, DateTime date) async {
    final photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo == null) return;

    final base = await _settings.baseUrl;
    final uploadUrl = '$base/uploadPhoto.php';
    final req = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    req.fields['patientId'] = patientId;
    req.fields['date']      = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
    req.files.add(await http.MultipartFile.fromPath('photo', photo.path));

    final res = await req.send();
    if (res.statusCode != 200) throw Exception('Ошибка загрузки: ${res.statusCode}');
  }
}
