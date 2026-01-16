import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class CaptureWindowsScreen extends StatefulWidget {
  const CaptureWindowsScreen({super.key});

  @override
  State<CaptureWindowsScreen> createState() => _CaptureWindowsScreenState();
}

class _CaptureWindowsScreenState extends State<CaptureWindowsScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initing = true;
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _cameras = await availableCameras(); // отдаст веб-камеру(ы)
      if (_cameras.isEmpty) {
        throw 'Нет доступных камер';
      }
      _controller = CameraController(
        _cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _controller!.initialize();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка камеры: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _initing = false);
    }
  }

  Future<void> _shoot() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _taking = true);
    try {
      final XFile xf = await _controller!.takePicture();
      // Сохраним во временную директорию
      final dir = await getTemporaryDirectory();
      final newPath = p.join(
        dir.path,
        'shot_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(xf.path).copy(newPath);

      if (mounted) Navigator.pop(context, newPath); // вернём путь
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сделать снимок: $e')),
      );
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Камера')),
        body: const Center(child: Text('Камера недоступна')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Сделать фото')),
      body: Center(
        child: AspectRatio(
          aspectRatio: _controller!.value.aspectRatio,
          child: CameraPreview(_controller!),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _taking ? null : _shoot,
        child: _taking
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.camera_alt),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
