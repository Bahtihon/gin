// lib/pages/patient_photo_screen.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;

import '../services/api_service.dart';

class PatientPhotoScreen extends StatefulWidget {
  final String fullName;
  final String dob;
  final String phone;
  final String appointmentTime;
  final String date;

  const PatientPhotoScreen({
    super.key,
    required this.fullName,
    required this.dob,
    required this.phone,
    required this.appointmentTime,
    required this.date,
  });

  @override
  State<PatientPhotoScreen> createState() => _PatientPhotoScreenState();
}

class _PatientPhotoScreenState extends State<PatientPhotoScreen> {
  bool _loading = false;
  List<String> _photos = [];

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    try {
      final files = await ApiService.fetchPhotoList(widget.fullName, widget.date);
      setState(() => _photos = List<String>.from(files));
    } catch (e) {
      debugPrint('Ошибка загрузки фото: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки фото: $e')),
        );
      }
    }
  }

  /// Универсальный выбор фото (Windows = FilePicker, Android = ImagePicker)
  Future<File?> _pickPhotoUniversal({bool fromCamera = false}) async {
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final res = await FilePicker.platform.pickFiles(type: FileType.image);
        if (res != null && res.files.single.path != null) {
          return File(res.files.single.path!);
        }
      } else {
        final ImagePicker picker = ImagePicker();
        final XFile? photo = await picker.pickImage(
          source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        );
        if (photo != null) return File(photo.path);
      }
    } catch (e) {
      debugPrint('Ошибка выбора фото: $e');
    }
    return null;
  }

  Future<void> _uploadPhoto(File file) async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(ApiService.baseUrl('upload_photo.php'));
      final req = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('photo', file.path))
        ..fields['fullName'] = widget.fullName
        ..fields['date'] = widget.date;

      final resp = await req.send();
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фото успешно загружено')),
        );
        _loadPhotos();
      } else {
        throw Exception('Ошибка ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('Ошибка загрузки фото: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки фото: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deletePhoto(String fileName) async {
    try {
      final resp = await ApiService.deletePhoto(widget.fullName, widget.date, fileName);
      if (resp == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фото удалено')),
        );
        _loadPhotos();
      } else {
        throw Exception(resp ?? 'Ошибка удаления');
      }
    } catch (e) {
      debugPrint('Ошибка удаления: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка удаления: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Фото — ${widget.fullName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPhotos,
            tooltip: 'Обновить',
          ),
          IconButton(
            icon: const Icon(Icons.add_a_photo),
            tooltip: 'Добавить фото',
            onPressed: () async {
              final file = await _pickPhotoUniversal(fromCamera: true);
              if (file != null) await _uploadPhoto(file);
            },
          ),
          IconButton(
            icon: const Icon(Icons.folder),
            tooltip: 'Выбрать из папки',
            onPressed: () async {
              final file = await _pickPhotoUniversal(fromCamera: false);
              if (file != null) await _uploadPhoto(file);
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? const Center(child: Text('Нет фото'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (ctx, i) {
                    final fileUrl = ApiService.baseUrl('photos/${_photos[i]}');
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Image.network(fileUrl, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deletePhoto(_photos[i]),
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}
