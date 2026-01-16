import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _ctrl = TextEditingController();
  final _settings = SettingsService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _ctrl.text = await _settings.baseUrl;
    setState(() {});
  }

  Future<void> _save() async {
    await _settings.setBaseUrl(_ctrl.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Адрес сервера сохранён'))
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Настройки')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                labelText: 'Базовый URL сервера',
                hintText: 'http://www.denta1.uz/'
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: _save,
              child: Text('Сохранить'),
            )
          ],
        ),
      ),
    );
  }
}
