// lib/pages/doctor_conclusion_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img_lib;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/settings_service.dart';
import '../services/api_service.dart';

class DoctorConclusionPage extends StatefulWidget {
  final int patientId;
  final String fullName;
  final String date;

  const DoctorConclusionPage({
    Key? key,
    required this.patientId,
    required this.fullName,
    required this.date,
  }) : super(key: key);

  @override
  State<DoctorConclusionPage> createState() => _DoctorConclusionPageState();
}

class _DoctorConclusionPageState extends State<DoctorConclusionPage> {
  final List<_ImageItem> _images = [];
  final List<String> _serverFiles = [];
  bool _loadingServer = false;
  bool _busy = false;
  final TextEditingController _textController = TextEditingController();

  final String _logDirName = 'logs';
  final String _logFileName = 'app_log.txt';

  @override
  void initState() {
    super.initState();
    _ensureLogDir();
    _loadServerFiles();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // ---------------- LOGGING ----------------
  Future<Directory> _appDir() async {
    try {
      final exePath = Platform.resolvedExecutable;
      if (exePath.isNotEmpty) {
        final exeDir = Directory(p.dirname(exePath));
        if (exeDir.existsSync()) return exeDir;
      }
    } catch (_) {}
    return Directory.current;
  }

  Future<File> _logFile() async {
    final d = await _appDir();
    final logs = Directory(p.join(d.path, _logDirName));
    if (!logs.existsSync()) logs.createSync(recursive: true);
    final f = File(p.join(logs.path, _logFileName));
    if (!f.existsSync()) f.createSync();
    return f;
  }

  Future<void> _log(String level, String msg) async {
    try {
      final f = await _logFile();
      final now = DateTime.now().toIso8601String();
      await f.writeAsString('[$now][$level] $msg\n', mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> _logInfo(String msg) async => _log('INFO', msg);
  Future<void> _logError(String msg) async => _log('ERROR', msg);

  Future<void> _ensureLogDir() async => _logInfo('DoctorConclusionPage opened');

  // ---------------- SERVER PHOTOS ----------------
  Future<void> _loadServerFiles() async {
    setState(() => _loadingServer = true);
    try {
      final files = await ApiService.fetchPhotoList(widget.fullName, widget.date);
      _serverFiles
        ..clear()
        ..addAll(files.map((e) => e.toString()));
      await _logInfo('Loaded ${_serverFiles.length} server photos');
    } catch (e, st) {
      await _logError('Failed to load server photos: $e\n$st');
    } finally {
      if (mounted) setState(() => _loadingServer = false);
    }
  }

  Future<String> _photoUrl(String filename) async {
    try {
      final base = await SettingsService().baseUrl;
      final safeFolder = '${widget.fullName}_${widget.date}';
      return Uri.parse(base)
          .replace(path: p.join(Uri.parse(base).path, 'photos', safeFolder, filename))
          .toString();
    } catch (e) {
      await _logError('photoUrl error: $e');
      return 'photos/${widget.fullName}_${widget.date}/$filename';
    }
  }

  // ---------------- LOCAL PICK & CROP ----------------
  Future<File?> _pickLocalImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      if (res == null || res.files.isEmpty) return null;
      return File(res.files.single.path!);
    } catch (e) {
      await _logError('pickLocalImage error: $e');
      return null;
    }
  }

  Future<File?> _cropImagePlatform(File srcFile) async {
    try {
      if (!Platform.isWindows && !kIsWeb) {
        final cropped = await ImageCropper().cropImage(
          sourcePath: srcFile.path,
          uiSettings: [
            AndroidUiSettings(toolbarTitle: 'Обрезать'),
            IOSUiSettings(title: 'Обрезать'),
          ],
        );
        if (cropped == null) return null;
        return File(cropped.path);
      } else {
        final File? edited = await Navigator.push<File?>(
          context,
          MaterialPageRoute(builder: (_) => _WindowsCropPage(imageFile: srcFile)),
        );
        return edited;
      }
    } catch (e, st) {
      await _logError('cropImage error: $e\n$st');
      return srcFile;
    }
  }

  Future<Uint8List> _prepareImageBytes(File f) async {
    final raw = await f.readAsBytes();
    final decoded = img_lib.decodeImage(raw);
    if (decoded == null) return raw;
    final out = img_lib.copyResize(decoded, width: decoded.width.clamp(0, 2000));
    return Uint8List.fromList(img_lib.encodeJpg(out, quality: 90));
  }

  Future<void> _addLocalImage() async {
    final f = await _pickLocalImage();
    if (f == null) return;
    final cropped = await _cropImagePlatform(f);
    final file = cropped ?? f;
    final bytes = await _prepareImageBytes(file);
    setState(() => _images.add(_ImageItem.local(bytes: bytes, name: p.basename(file.path))));
    await _logInfo('Added local image ${file.path}');
  }
  Future<void> _addServerImage(String filename) async {
    try {
      final url = await _photoUrl(filename);
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      final bytes = await consolidateHttpClientResponseBytes(resp);
      if (resp.statusCode != 200) {
        final body = utf8.decode(bytes, allowMalformed: true);
        await _logError('Server download fail ${resp.statusCode}: $body');
        return;
      }
      final tmp = await getTemporaryDirectory();
      final tmpFile = File(p.join(tmp.path, filename));
      await tmpFile.writeAsBytes(bytes);
      final cropped = await _cropImagePlatform(tmpFile);
      final file = cropped ?? tmpFile;
      final prepared = await _prepareImageBytes(file);
      setState(() => _images.add(_ImageItem.server(bytes: prepared, name: filename, originalUrl: url)));
      await _logInfo('Added server image $filename');
    } catch (e, st) {
      await _logError('addServerImage error: $e\n$st');
    }
  }

  // ---------------- PDF GENERATION ----------------
  static const double _photoSizeCm = 6.0;
  static const double _cmToPt = 28.3465;
  static final double _photoSizePt = _photoSizeCm * _cmToPt;

  Future<Uint8List> _generatePdf(String text) async {
    final pdf = pw.Document();
    pw.Font ttf;
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      ttf = pw.Font.ttf(fontData);
    } catch (e, st) {
      await _logError('Font load failed: $e\n$st');
      ttf = pw.Font.helvetica();
    }

    final widgets = <pw.Widget>[];
    for (int i = 0; i < _images.length; i += 2) {
      final row = <pw.Widget>[];
      row.add(_pdfImage(_images[i]));
      if (i + 1 < _images.length) row.add(pw.SizedBox(width: 10));
      if (i + 1 < _images.length) row.add(_pdfImage(_images[i + 1]));
      widgets.add(pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: row));
      widgets.add(pw.SizedBox(height: 10));
    }
    widgets.add(pw.Text(text, style: pw.TextStyle(font: ttf, fontSize: 12)));
    widgets.add(pw.Spacer());
    widgets.add(pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('GynoApp © ${DateTime.now().year}', style: pw.TextStyle(font: ttf, fontSize: 8))));

    pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4, build: (_) => pw.Column(children: widgets)));
    return pdf.save();
  }

  pw.Widget _pdfImage(_ImageItem it) => pw.Container(
        width: _photoSizePt,
        height: _photoSizePt,
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
        child: pw.Image(pw.MemoryImage(it.bytes), fit: pw.BoxFit.cover),
      );

  Future<void> _savePdf(Uint8List bytes) async {
    try {
      Directory dir;
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      dir = Directory(p.join(home ?? Directory.current.path, 'Documents', 'Conclusions'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final path = p.join(dir.path, '${widget.fullName}_${widget.date}.pdf');
      await File(path).writeAsBytes(bytes);
      await _logInfo('Saved PDF $path');
    } catch (e, st) {
      await _logError('savePdf error: $e\n$st');
    }
  }

  // ---------------- UI ----------------
  Widget _buildServerList() {
    if (_loadingServer) return const Center(child: CircularProgressIndicator());
    if (_serverFiles.isEmpty) return const Center(child: Text('Нет снимков на сервере'));
    return ListView.builder(
      itemCount: _serverFiles.length,
      itemBuilder: (c, i) => ListTile(
        title: Text(_serverFiles[i], overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => _addServerImage(_serverFiles[i]),
        ),
      ),
    );
  }

  Widget _buildImages() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(_images.length, (i) {
          final it = _images[i];
          return Stack(children: [
            Container(width: 120, height: 120, child: Image.memory(it.bytes, fit: BoxFit.cover)),
            Positioned(
              right: 0,
              top: 0,
              child: IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
                onPressed: () => setState(() => _images.removeAt(i)),
              ),
            )
          ]);
        }),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Заключение — ${widget.fullName} (${widget.date})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Предпросмотр и PDF',
            onPressed: () async {
              final pdf = await _generatePdf(_textController.text);
              await Printing.layoutPdf(onLayout: (_) async => pdf);
              await _savePdf(pdf);
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_copy),
            tooltip: 'Шаблоны (позже)',
            onPressed: () => _logInfo('Template button pressed'),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                SizedBox(
                  width: 300,
                  child: Card(
                    child: Column(children: [
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('Снимки на сервере', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Expanded(child: _buildServerList()),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Обновить'),
                        onPressed: _loadServerFiles,
                      )
                    ]),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add_photo_alternate),
                          label: const Text('Добавить фото'),
                          onPressed: _addLocalImage,
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.clear),
                          label: const Text('Очистить'),
                          onPressed: () => setState(() => _images.clear()),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      _buildImages(),
                      const SizedBox(height: 10),
                      const Text('Текст заключения', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextField(
                        controller: _textController,
                        maxLines: 10,
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
    );
  }
}

// ------------ ImageItem ------------
class _ImageItem {
  final Uint8List bytes;
  final String name;
  final String? originalUrl;
  final bool isLocal;
  _ImageItem._(this.bytes, this.name, this.originalUrl, this.isLocal);

  factory _ImageItem.local({required Uint8List bytes, required String name}) =>
      _ImageItem._(bytes, name, null, true);
  factory _ImageItem.server({required Uint8List bytes, required String name, required String originalUrl}) =>
      _ImageItem._(bytes, name, originalUrl, false);
}

// ------------ Windows Cropper с рамкой 6x6 см ------------
class _WindowsCropPage extends StatefulWidget {
  final File imageFile;
  const _WindowsCropPage({required this.imageFile});
  @override
  State<_WindowsCropPage> createState() => _WindowsCropPageState();
}

class _WindowsCropPageState extends State<_WindowsCropPage> {
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  late Uint8List _bytes;
  bool _loaded = false;

  final GlobalKey _cropKey = GlobalKey();

  // Размер рамки 6x6 см при 96 dpi ≈ 226 px
  static const double _cropSize = 226;

  @override
  void initState() {
    super.initState();
    widget.imageFile.readAsBytes().then((b) {
      setState(() {
        _bytes = b;
        _loaded = true;
      });
    });
  }

  Future<File?> _captureCropped() async {
    try {
      RenderRepaintBoundary boundary = _cropKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 1.5);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      Uint8List pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final croppedPath = p.join(tempDir.path, 'cropped_${DateTime.now().millisecondsSinceEpoch}.png');
      final croppedFile = File(croppedPath);
      await croppedFile.writeAsBytes(pngBytes);
      return croppedFile;
    } catch (e, st) {
      debugPrint('❌ Crop save error: $e\n$st');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Обрезка снимка (6×6 см)'),
        actions: [
          TextButton(
            onPressed: () async {
              final f = await _captureCropped();
              Navigator.pop(context, f ?? widget.imageFile);
            },
            child: const Text('Сохранить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              alignment: Alignment.center,
              children: [
                // Обрезаем видимую область в RepaintBoundary
                RepaintBoundary(
                  key: _cropKey,
                  child: ClipRect(
                    child: Container(
                      width: _cropSize,
                      height: _cropSize,
                      color: Colors.black,
                      child: GestureDetector(
                        onPanUpdate: (d) => setState(() => _offset += d.delta),
                        onScaleUpdate: (s) => setState(() => _scale *= s.scale),
                        child: Transform.translate(
                          offset: _offset,
                          child: Transform.scale(
                            scale: _scale,
                            child: Image.memory(_bytes, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Полупрозрачная затемнённая маска вокруг рамки
                IgnorePointer(
                  child: Container(
                    color: Colors.black.withOpacity(0.5),
                    child: Center(
                      child: Container(
                        width: _cropSize,
                        height: _cropSize,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.redAccent, width: 2),
                          color: Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ),

                // Подсказка управления
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: 60,
                    color: Colors.black.withOpacity(0.6),
                    child: const Center(
                      child: Text(
                        '🖱 Перемещение — мышью | 🔍 Масштаб — колесиком | 💾 Сохранить — сверху',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

