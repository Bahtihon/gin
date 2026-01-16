import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'patient_photo_screen.dart';

class PatientList extends StatefulWidget {
  @override
  _PatientListState createState() => _PatientListState();
}

class _PatientListState extends State<PatientList> {
  final String serverIp = 'www.denta1.uz';
  DateTime _selectedDate = DateTime.now();
  List<dynamic> _patients = [];
  final Map<String, int> _photoCounts = {};

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  void _changeDate(int offsetDays) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: offsetDays)));
    _loadPatients();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadPatients();
    }
  }

  Future<void> _loadPatients() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final uri = Uri.parse('http://$serverIp/api.php?date=$dateStr');
    try {
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final List<dynamic> patients = json.decode(utf8.decode(resp.bodyBytes));
        setState(() {
          _patients = patients;
          _photoCounts.clear();
        });
        for (var p in _patients) {
          final fullName = p['fullName'] as String? ?? '';
          _fetchPhotoCount(fullName, dateStr);
        }
      } else {
        throw Exception('Ошибка ${resp.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не удалось загрузить: $e')));
    }
  }

  Future<void> _fetchPhotoCount(String fullName, String dateStr) async {
    final uri = Uri.parse(
      'http://$serverIp/photo_list.php'
      '?fullName=${Uri.encodeComponent(fullName)}'
      '&date=$dateStr',
    );
    try {
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final List<dynamic> files = json.decode(utf8.decode(resp.bodyBytes));
        setState(() => _photoCounts[fullName] = files.length);
      } else {
        setState(() => _photoCounts[fullName] = 0);
      }
    } catch (_) {
      setState(() => _photoCounts[fullName] = 0);
    }
  }

  Widget _buildTriangleButton({required bool left, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Transform.rotate(
            angle: left ? math.pi : 0.0,
            child: const Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  /// Прямоугольная кнопка "СЕГОДНЯ"
  Widget _buildTodayButton() {
    return GestureDetector(
      onTap: () {
        setState(() => _selectedDate = DateTime.now());
        _loadPatients();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'СЕГОДНЯ',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayDate = DateFormat('dd.MM.yyyy').format(_selectedDate);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _buildTriangleButton(left: true, onTap: () => _changeDate(-1)),
            const Spacer(),
            GestureDetector(
              onTap: _pickDate,
              child: Text(
                displayDate,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            _buildTodayButton(),
            const Spacer(),
            _buildTriangleButton(left: false, onTap: () => _changeDate(1)),
          ],
        ),
      ),
      body: _patients.isEmpty
          ? const Center(child: Text('Нет приёмов на эту дату'))
          : ListView.builder(
              itemCount: _patients.length,
              itemBuilder: (ctx, i) {
                final p = _patients[i];
                final fullName = p['fullName'] as String? ?? '';
                final dob = p['dob'] as String? ?? '';
                final phone = p['phone'] as String? ?? '';
                final datetime = p['appointment_datetime'] as String? ?? '';
                final time = datetime.contains(' ')
                    ? datetime.split(' ')[1].substring(0, 5)
                    : '';
                final count = _photoCounts[fullName] ?? 0;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(fullName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Дата рожд.: $dob'),
                        Text('Телефон: $phone'),
                        Text('Время: $time'),
                      ],
                    ),
                    trailing: CircleAvatar(
                      radius: 18,
                      backgroundColor: count > 0 ? Colors.green : Colors.red,
                      child: count > 0
                          ? Text(
                              count.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : const Icon(Icons.remove, size: 16, color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PatientPhotoScreen(
                            fullName: fullName,
                            dob: dob,
                            phone: phone,
                            appointmentTime: time,
                            date: dateStr,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: FloatingActionButton(
          onPressed: _loadPatients,
          tooltip: 'Обновить список',
          child: const Icon(Icons.refresh),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
