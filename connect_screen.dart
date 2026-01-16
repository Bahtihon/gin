// lib/pages/connect_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'remote_control_screen.dart';

// Модель устройства
class Device {
  final int id;
  final String ip;
  final int port;
  final String name;

  Device({
    required this.id,
    required this.ip,
    required this.port,
    required this.name,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: int.parse(json['id'] as String),
      ip: json['ip'] as String,
      port: int.parse(json['port'] as String),
      name: json['device_name'] as String,
    );
  }
}

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({Key? key}) : super(key: key);

  @override
  _ConnectScreenState createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final String _server = 'https://www.denta1.uz';
  List<Device> _devices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchDevices();
  }

  Future<void> _fetchDevices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('$_server/devices.php');
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final List<dynamic> data = json.decode(resp.body);
        setState(() {
          _devices = data.map((e) => Device.fromJson(e)).toList();
          _loading = false;
        });
      } else {
        throw Exception('HTTP ${resp.statusCode}');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Выбор устройства'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchDevices,
            tooltip: 'Обновить список',
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Ошибка: $_error'))
              : ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (_, i) {
                    final d = _devices[i];
                    return ListTile(
                      leading: Icon(Icons.device_hub),
                      title: Text(d.name),
                      subtitle: Text('${d.ip}:${d.port}'),
                      onTap: () {
                        // Переходим в экран управления, передаём нужные параметры
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RemoteControlScreen(
                              ip: d.ip,
                              port: d.port,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
