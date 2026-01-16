// lib/pages/patient_photo_pc.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path/path.dart' as path;

import '../services/api.dart';
import '../widgets/camera_panel.dart';

class PatientPhotoPC extends StatefulWidget {
  final String fullName;
  final String dob;
  final String phone;
  final String appointmentTime;
  final String date;

  const PatientPhotoPC({
    super.key,
    required this.fullName,
    required this.dob,
    required this.phone,
    required this.appointmentTime,
    required this.date,
  });

  @override
  State<PatientPhotoPC> createState() => _PatientPhotoPCState();
}

class _PatientPhotoPCState extends State<PatientPhotoPC> {
  final List<String> _localShots = []; // пути к локальным фото
  List<String> _serverFiles = [];
  bool _uploading = false;

  String get _folderName => '${widget.fullName}_${widget.date}';

  @override
  void initState() {
    super.initState();
    _fetchPhotoPaths();
  }

  Future<void> _fetchPhotoPaths() async {
    final uri = Uri.parse(
      baseUrl('photo_list.php') +
          '?fullName=${Uri.encodeComponent(widget.fullName)}'
          '&date=${widget.date}',
    );
    final res = await http.get(uri);
    if (!mounted) return;
    if (res.statusCode == 200) {
      final raw = json.decode(utf8.decode(res.bodyBytes));
      final files = <String>[];
      if (raw is List) {
        for (var item in raw) {
          if (item is String) files.add(item);
          else if (item is Map && item['file'] is String) files.add(item['file']);
        }
      }
      setState(() => _serverFiles = files);
    }
  }

  void _onPictureTaken(String filePath) {
    setState(() => _localShots.add(filePath));
  }

  void _removeLocal(int index) {
    final f = _localShots.removeAt(index);
    File(f).delete().ignore();
    setState(() {});
  }

  Future<void> _uploadAll() async {
    if (_localShots.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нужно минимум 2 фото')),
      );
      return;
    }
    setState(() => _uploading = true);

    final uri = Uri.parse(baseUrl('upload.php'));
    final req = http.MultipartRequest('POST', uri)
      ..fields['fullName'] = widget.fullName
      ..fields['date'] = widget.date;

    for (var f in _localShots) {
      req.files.add(await http.MultipartFile.fromPath(
        'photos[]',
        f,
        filename: path.basename(f),
      ));
    }

    final resp = await req.send();
    final body = await resp.stream.bytesToString();
    debugPrint('UPLOAD ${resp.statusCode}: $body');

    if (!mounted) return;

    if (resp.statusCode == 200) {
      await _fetchPhotoPaths();
      // чистим локальные
      for (var f in _localShots) {
        File(f).delete().ignore();
      }
      setState(() => _localShots.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Фото успешно загружены')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: ${resp.statusCode}')),
      );
    }
    setState(() => _uploading = false);
  }

  Future<void> _confirmDelete(String fileName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить фото?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final relPath = fileName.contains('photos/')
        ? fileName
        : 'photos/$_folderName/$fileName';

    final uri = Uri.parse(baseUrl('delete_photo.php'));
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'path': relPath}),
    );

    if (!mounted) return;

    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      if (data['success'] == true) {
        await _fetchPhotoPaths();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фото удалено')),
        );
      } else {
        final err = data['error'] ?? 'Неизвестная ошибка';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка удаления: $err')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('HTTP ${res.statusCode} при удалении')),
      );
    }
  }

  void _viewImage({String? url, File? file}) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          panEnabled: true,
          child: file != null
              ? Image.file(file)
              : Image.network(url!, fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = !_uploading;

    return Scaffold(
      appBar: AppBar(title: const Text('Фото пациента (ПК)')),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Text(widget.fullName, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text('Дата рождения: ${widget.dob}'),
          Text('Телефон: ${widget.phone}', overflow: TextOverflow.visible),
          Text('Время приёма: ${widget.appointmentTime}'),
          const Divider(),

          Expanded(
            flex: 3,
            child: CameraPanel(
              onPictureTaken: (path) {
                _onPictureTaken(path);
              },
            ),
          ),

          const Divider(),

          // Локальные (ещё не загруженные) кадры
          if (_localShots.isNotEmpty) ...[
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _localShots.length,
                itemBuilder: (_, i) {
                  final f = _localShots[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: () => _viewImage(file: File(f)),
                          child: Image.file(File(f),
                              width: 100, height: 100, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeLocal(i),
                            child: Container(
                              color: Colors.black54,
                              padding: const EdgeInsets.all(4),
                              child: const Icon(Icons.close,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(),
          ],

          // Фото на сервере
          Expanded(
            flex: 2,
            child: _serverFiles.isEmpty
                ? const Center(child: Text('Фото на сервере не найдены'))
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                    itemCount: _serverFiles.length,
                    itemBuilder: (_, i) {
                      final fn = _serverFiles[i];
                      final rel = fn.contains('photos/')
                          ? fn
                          : 'photos/$_folderName/$fn';
                      final rawUrl = baseUrl(rel);
                      final url = Uri.encodeFull(rawUrl);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          GestureDetector(
                            onTap: () => _viewImage(url: url),
                            child: Image.network(url, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _confirmDelete(fn),
                              child: Container(
                                decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // "Сделать фото" уже в CameraPanel
                ElevatedButton(
                  onPressed: _localShots.length >= 2 && !_uploading ? _uploadAll : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Сохранить (загрузить)'),
                ),
                ElevatedButton.icon(
                  onPressed: _fetchPhotoPaths,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Обновить список фото'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
