// lib/desktop/desktop_home.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'dart:async';

import '../pages/patient_photo_screen.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../pages/doctor_conclusion_page.dart';

class DesktopHome extends StatefulWidget {
  const DesktopHome({super.key});

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  Timer? _searchDebounce;
  DateTime _selectedDate = DateTime.now();
  List<dynamic> _patients = [];
  List<dynamic> _filteredPatients = [];
  final Map<String, int> _photoCounts = {};
  bool _loading = false;
  bool _isAdmin = false;
  String? _lastError;
  Set<String> _busyDates = {};


  final SettingsService _settings = SettingsService();

  // --- поиск
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _dobCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initSettingsAndLoad();
	_loadBusyDates();
  }

  Future<void> _initSettingsAndLoad() async {
    try {
      final admin = await _settings.isAdminMode;
      setState(() => _isAdmin = admin == true);
    } catch (_) {
      setState(() => _isAdmin = false);
    }
    await _loadAppointments();
  }

Future<void> _loadBusyDates() async {
  try {
    final allPatients = await ApiService.fetchPatients(""); // без даты — все пациенты
    final Set<String> dates = {};
    for (var p in allPatients) {
      final appt = p['appointment_datetime'] as String? ?? '';
      if (appt.isEmpty) continue;
      try {
        final dt = DateTime.parse(appt);
        dates.add(DateFormat('yyyy-MM-dd').format(dt));
      } catch (_) {}
    }
    if (mounted) setState(() => _busyDates = dates);
  } catch (e) {
    print("Ошибка загрузки busyDates: $e");
  }
}


  Future<void> _loadAppointments() async {
    setState(() {
      _loading = true;
      _lastError = null;
    });
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    try {
      final patients = await ApiService.fetchPatients(dateStr);
      final safeList = (patients is List) ? patients : <dynamic>[];
      setState(() {
        _patients = safeList;
        _filteredPatients = List.from(safeList);
        _photoCounts.clear();
      });
      for (var p in _patients) {
        final fullName = p['fullName'] as String? ?? '';
        _fetchPhotoCount(fullName, dateStr);
      }
    } catch (e) {
      setState(() {
        _patients = [];
        _filteredPatients = [];
        _lastError = e.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchPhotoCount(String fullName, String dateStr) async {
    try {
      final files = await ApiService.fetchPhotoList(fullName, dateStr);
      final count = (files is List) ? files.length : 0;
      if (mounted) setState(() => _photoCounts[fullName] = count);
    } catch (_) {
      if (mounted) setState(() => _photoCounts[fullName] = 0);
    }
  }

  void _pickDate(DateTime d) {
    setState(() {
      _selectedDate = d;
      _filteredPatients = List.from(_patients);
    });
    _loadAppointments();
  }

  void _goToday() {
    setState(() {
      _selectedDate = DateTime.now();
      _filteredPatients = List.from(_patients);
    });
    _loadAppointments();
  }

  void _resetFilter() {
    setState(() {
      _filteredPatients = List.from(_patients);
      _nameCtrl.clear();
      _dobCtrl.clear();
      _phoneCtrl.clear();
    });
  }

Future<void> _createAppointmentForExisting(Map<String, dynamic> patient) async {
  final TextEditingController complaintCtrl = TextEditingController();
  DateTime selectedDate = DateTime.now();
  TimeOfDay selectedTime = TimeOfDay.now();

  final maskApptTime = MaskTextInputFormatter(
    mask: '##:##',
    filter: {"#": RegExp(r'\d')},
  );
  final TextEditingController apptTimeCtrl =
      TextEditingController(text: DateFormat('HH:mm').format(DateTime.now()));

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setStateDialog) => AlertDialog(
        title: Text('Новый приём — ${patient['fullName']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- выбор даты ---
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Дата приёма: ${DateFormat('dd.MM.yyyy').format(selectedDate)}',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.calendar_month, color: Colors.blue),
                    tooltip: 'Выбрать дату',
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        locale: const Locale('ru', 'RU'),
                      );
                      if (picked != null) {
                        setStateDialog(() => selectedDate = picked);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // --- выбор времени ---
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: apptTimeCtrl,
                      inputFormatters: [maskApptTime],
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Время (HH:MM)'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.access_time, color: Colors.blue),
                    tooltip: 'Выбрать время',
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setStateDialog(() {
                          selectedTime = picked;
                          apptTimeCtrl.text =
                              picked.format(ctx).padLeft(5, '0');
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // --- жалобы ---
              TextField(
                controller: complaintCtrl,
                decoration:
                    const InputDecoration(labelText: 'Жалобы / Примечание'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            child: const Text('Создать'),
            onPressed: () async {
              final dateStr =
                  DateFormat('yyyy-MM-dd').format(selectedDate);
              final timeStr = apptTimeCtrl.text.trim();
              final dateTimeDb = '$dateStr $timeStr:00';

              try {
                final resp = await ApiService.addAppointment({
                  'fullName': patient['fullName'],
                  'dob': patient['dob'],
                  'phone': patient['phone'],
                  'address': patient['address'] ?? '',
                  'complaint': complaintCtrl.text.trim(),
                  'appointment_datetime': dateTimeDb,
                });

                if (resp['success'] == true) {
                  Navigator.pop(ctx);
                  await _loadAppointments();
                  _loadBusyDates();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Новый приём добавлен')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Ошибка: ${resp['error'] ?? 'Не удалось добавить'}')),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ошибка: $e')),
                );
              }
            },
          ),
        ],
      ),
    ),
  );
}


  // --- ADMIN MODE ---
  Future<void> _toggleAdminMode() async {
    if (_isAdmin) {
      // выключить по долгому нажатию
      setState(() => _isAdmin = false);
      await _settings.setAdminMode(false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Админ режим выключен')));
      return;
    }

    final TextEditingController passCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Админ-доступ'),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Введите пароль'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, passCtrl.text.trim() == '12345'), child: const Text('Войти')),
        ],
      ),
    );

    if (ok == true) {
      setState(() => _isAdmin = true);
      await _settings.setAdminMode(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Админ режим включен')));
    } else if (ok == false && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Неверный пароль администратора')));
    }
  }

  Future<void> _showSearchDialog() async {
  await showDialog(
    context: context,
    builder: (ctx) {
      final localNameCtrl = TextEditingController(text: _nameCtrl.text);

      Future<void> performLiveSearch(String value) async {
        _searchDebounce?.cancel();

        final query = value.trim();
        if (query.length < 3) {
          // если меньше 3 символов — очищаем фильтр и не ищем
          setState(() => _filteredPatients = List.from(_patients));
          return;
        }

        _searchDebounce = Timer(const Duration(seconds: 1), () async {
          try {
            final results = await ApiService.searchPatients(query);
            if (mounted) {
              setState(() {
                _filteredPatients = results;
              });
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Ошибка поиска: $e')),
              );
            }
          }
        });
      }

      return AlertDialog(
        title: const Text('Поиск пациентов'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: localNameCtrl,
              decoration: const InputDecoration(
                labelText: 'ФИО / Телефон / Год',
                hintText: 'Введите минимум 3 символа...',
              ),
              onChanged: (v) => performLiveSearch(v),
            ),
            const SizedBox(height: 6),
            const Text(
              'Поиск выполняется автоматически через 1 секунду\nпосле остановки ввода (минимум 3 символа)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              // Сброс поиска
              setState(() {
                _filteredPatients = List.from(_patients);
                _nameCtrl.clear();
                _dobCtrl.clear();
                _phoneCtrl.clear();
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Поиск сброшен')),
              );
            },
            child: const Text('Сбросить'),
          ),
        ],
      );
    },
  );
}


  // --- форма add/edit пациента ---
  Future<void> _showAddOrEditDialog({Map<String, dynamic>? patient}) async {
    final isEdit = patient != null;

    final TextEditingController nameCtrl = TextEditingController(text: patient?['fullName'] ?? '');
    final maskDob = MaskTextInputFormatter(mask: '##.##.####', filter: {"#": RegExp(r'\d')});
    final TextEditingController dobCtrl = TextEditingController(text: _formatDateDisplay(patient?['dob'] ?? ''));
    final phoneMask = MaskTextInputFormatter(mask: '+998 (##) ###-##-##', filter: {"#": RegExp(r'\d')});
    final TextEditingController phoneCtrl = TextEditingController(text: patient?['phone'] ?? '');
    final TextEditingController addressCtrl = TextEditingController(text: patient?['address'] ?? '');
    final TextEditingController complaintCtrl = TextEditingController(text: patient?['complaint'] ?? '');

    String apptDateDisplay = _formatDateDisplay(patient?['appointment_datetime'] ?? '');
    String apptTimeDisplay = _formatTimeDisplay(patient?['appointment_datetime'] ?? '');
    if (apptDateDisplay.isEmpty) {
      apptDateDisplay = DateFormat('dd.MM.yyyy').format(_selectedDate);
      apptTimeDisplay = DateFormat('HH:mm').format(DateTime.now());
    }

    final maskApptDate = MaskTextInputFormatter(mask: '##.##.####', filter: {"#": RegExp(r'\d')});
    final maskApptTime = MaskTextInputFormatter(mask: '##:##', filter: {"#": RegExp(r'\d')});
    final TextEditingController apptDateCtrl = TextEditingController(text: apptDateDisplay);
    final TextEditingController apptTimeCtrl = TextEditingController(text: apptTimeDisplay);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Редактировать пациента' : 'Новый приём'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'ФИО')),
              TextField(controller: dobCtrl, decoration: const InputDecoration(labelText: 'Дата рождения (ДД.MM.ГГГГ)'), keyboardType: TextInputType.number, inputFormatters: [maskDob]),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Телефон (+998 (##) ###-##-##)'), keyboardType: TextInputType.phone, inputFormatters: [phoneMask]),
              TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Адрес')),
              TextField(controller: complaintCtrl, decoration: const InputDecoration(labelText: 'Жалобы / Примечание'), maxLines: 2),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: apptDateCtrl, decoration: const InputDecoration(labelText: 'Дата приёма (ДД.MM.ГГГГ)'), inputFormatters: [maskApptDate], keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  SizedBox(width: 110, child: TextField(controller: apptTimeCtrl, decoration: const InputDecoration(labelText: 'Время (HH:MM)'), inputFormatters: [maskApptTime], keyboardType: TextInputType.number)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              final fullName = nameCtrl.text.trim();
              final dobInput = dobCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              final address = addressCtrl.text.trim();
              final complaint = complaintCtrl.text.trim();
              final apptDateInput = apptDateCtrl.text.trim();
              final apptTimeInput = apptTimeCtrl.text.trim();

              if (fullName.isEmpty || dobInput.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ФИО и дата рождения обязательны')));
                return;
              }

              String dobForDb = _formatDateForDb(dobInput);
              String appointmentDatetimeForDb = _combineDateTimeForDb(apptDateInput, apptTimeInput);

              try {
                if (isEdit) {
                  final id = patient!['id'];
                  final result = await ApiService.updatePatient(id, {
                    'fullName': fullName,
                    'dob': dobForDb,
                    'phone': phone,
                    'address': address,
                    'complaint': complaint,
                    'appointment_datetime': appointmentDatetimeForDb,
                  });
                  if (result['success'] == true) {
                    Navigator.pop(ctx);
                    await _loadAppointments();
					_loadBusyDates();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пациент обновлён')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: ${result['error'] ?? '...'}')));
                  }
                } else {
                  // При добавлении отправляем date + текущее время
                  final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
                  final nowTime = DateFormat('HH:mm').format(DateTime.now());
                  final resp = await ApiService.addPatient({
                    'fullName': fullName,
                    'dob': dobForDb,
                    'phone': phone,
                    'address': address,
                    // теперь отправляем полный appointment datetime в поле date
                    'date': '$dateStr $nowTime:00',
                  });
                  if (resp['success'] == true) {
                    Navigator.pop(ctx);
                    await _loadAppointments();
					_loadBusyDates();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Новый приём добавлен')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: ${resp['error'] ?? '...'}')));
                  }
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
              }
            },
            child: Text(isEdit ? 'Сохранить' : 'Добавить'),
          ),
        ],
      ),
    );
  }

  String _formatDateDisplay(String value) {
    if (value.isEmpty) return '';
    try {
      final dt = DateTime.parse(value);
      return DateFormat('dd.MM.yyyy').format(dt);
    } catch (_) {
      return value;
    }
  }

  String _formatTimeDisplay(String value) {
    if (value.isEmpty) return '';
    try {
      final dt = DateTime.parse(value);
      return DateFormat('HH:mm').format(dt);
    } catch (_) {
      return '';
    }
  }

  String _formatDateForDb(String ddmmyyyy) {
    final parts = ddmmyyyy.split('.');
    if (parts.length != 3) return ddmmyyyy;
    return '${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
  }

  String _combineDateTimeForDb(String dateInput, String timeInput) {
    final dparts = dateInput.split('.');
    if (dparts.length != 3) {
      // fallback to today
      final today = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final timePart = (timeInput.isNotEmpty) ? timeInput : '00:00';
      return '$today $timePart:00';
    }
    final datePart = '${dparts[2]}-${dparts[1].padLeft(2, '0')}-${dparts[0].padLeft(2, '0')}';
    final timePart = (timeInput.isNotEmpty) ? timeInput : '00:00';
    return '$datePart $timePart:00';
  }

  Future<void> _confirmAndDelete(int id) async {
    if (!_isAdmin) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить пациента'),
        content: const Text('Вы уверены? Это действие необратимо.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final res = await ApiService.deletePatient(id);
      if (res['success'] == true) {
        await _loadAppointments();
		_loadBusyDates();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Пациент удалён')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: ${res['error'] ?? '...'}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка удаления: $e')));
    }
  }
@override
void dispose() {
  _searchDebounce?.cancel();
  super.dispose();
}

Widget _buildCustomCalendar() {
  // Начало месяца
  final firstDayOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);

  // В Dart понедельник = 1, воскресенье = 7.
  // Сделаем так, чтобы понедельник был колонкой 0, воскресенье — колонкой 6.
  int startWeekday = firstDayOfMonth.weekday - 1; // 0..6
  if (startWeekday < 0) startWeekday = 6; // на всякий случай

  // Количество дней в месяце
  final nextMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
  final daysInMonth = nextMonth.subtract(const Duration(days: 1)).day;

  // Сегодняшняя дата
  final today = DateTime.now();

  // Заголовки дней недели
  final daysOfWeek = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  // Используем _busyDates — набор строк 'yyyy-MM-dd' для дат с приёмами
  final Set<String> busyDates = _busyDates;

  final List<TableRow> rows = [];

  // --- заголовок таблицы: дни недели ---
  rows.add(
    TableRow(
      children: daysOfWeek.map((d) {
        final isSunday = d == 'Вс';
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              d,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSunday ? Colors.red : Colors.black,
              ),
            ),
          ),
        );
      }).toList(),
    ),
  );

  // --- тело календаря ---
  int dayCounter = 1;
  for (int week = 0; week < 6; week++) {
    final List<Widget> cells = [];
    for (int weekday = 0; weekday < 7; weekday++) {
      final isDaySlot =
          (week > 0 || weekday >= startWeekday) && dayCounter <= daysInMonth;
      if (isDaySlot) {
        final currentDate =
            DateTime(_selectedDate.year, _selectedDate.month, dayCounter);
        final dateKey = DateFormat('yyyy-MM-dd').format(currentDate);

        final isSelected =
            currentDate.day == _selectedDate.day &&
            currentDate.month == _selectedDate.month &&
            currentDate.year == _selectedDate.year;
        final isToday =
            currentDate.day == today.day &&
            currentDate.month == today.month &&
            currentDate.year == today.year;
        final isSunday = weekday == 6; // воскресенье — последняя колонка
        final hasPatients = busyDates.contains(dateKey);

        cells.add(
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedDate = currentDate;
              });
              _loadAppointments();
            },
            child: Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isSunday
                        ? Colors.red.withOpacity(0.3)
                        : Colors.blue.withOpacity(0.3))
                    : Colors.transparent,
                border: isToday
                    ? Border.all(
                        color: Colors.blueAccent,
                        width: 1.5,
                      )
                    : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$dayCounter',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSunday
                          ? Colors.red
                          : (isSelected ? Colors.black : Colors.black87),
                    ),
                  ),
                  if (hasPatients)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.circle,
                        size: 7,
                        color: isSunday ? Colors.redAccent : Colors.blueAccent,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        dayCounter++;
      } else {
        cells.add(Container());
      }
    }
    rows.add(TableRow(children: cells));
  }

  return Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 12),
    child: Table(children: rows),
  );
}



  @override
  Widget build(BuildContext context) {
    final displayDate = DateFormat('dd.MM.yyyy').format(_selectedDate);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: Text('Регистратор — $displayDate'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Обновить', onPressed: _loadAppointments),
          IconButton(icon: const Icon(Icons.person_add), tooltip: 'Новый приём', onPressed: () => _showAddOrEditDialog()),
          IconButton(icon: const Icon(Icons.search), tooltip: 'Поиск', onPressed: _showSearchDialog),
          GestureDetector(
            onLongPress: _toggleAdminMode,
            child: IconButton(
              icon: Icon(_isAdmin ? Icons.vpn_key : Icons.vpn_key_outlined),
              tooltip: _isAdmin ? 'Выключить админ режим' : 'Включить админ режим',
              onPressed: _toggleAdminMode,
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 320,
            child: Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    // === Календарь с панелью переключения дат ===

const SizedBox(height: 8),

// === Календарь с панелью переключения месяцев ===
Text(
  'Выбор даты',
  style: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: _selectedDate.weekday == DateTime.sunday
        ? Colors.red
        : Colors.black,
  ),
),

// --- панель навигации по месяцам ---
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    IconButton(
      icon: const Icon(Icons.chevron_left, size: 30),
      tooltip: 'Предыдущий месяц',
      onPressed: () {
        setState(() {
          _selectedDate = DateTime(
            _selectedDate.year,
            _selectedDate.month - 1,
            1,
          );
        });
        _loadBusyDates(); // 👈 обновляем точки для нового месяца
      },
    ),
    Text(
      DateFormat('LLLL yyyy', 'ru_RU').format(_selectedDate),
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
    IconButton(
      icon: const Icon(Icons.chevron_right, size: 30),
      tooltip: 'Следующий месяц',
      onPressed: () {
        setState(() {
          _selectedDate = DateTime(
            _selectedDate.year,
            _selectedDate.month + 1,
            1,
          );
        });
        _loadBusyDates(); // 👈 обновляем точки для нового месяца
      },
    ),
  ],
),

// --- сам календарь ---
_buildCustomCalendar(),

const SizedBox(height: 8),

// --- панель навигации по дням ---
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    IconButton(
      icon: const Icon(Icons.arrow_left, size: 30),
      tooltip: 'Предыдущий день',
      onPressed: () {
        setState(() {
          _selectedDate = _selectedDate.subtract(const Duration(days: 1));
        });
        _loadAppointments();
      },
    ),
    Text(
      DateFormat('dd.MM.yyyy', 'ru_RU').format(_selectedDate),
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: _selectedDate.weekday == DateTime.sunday
            ? Colors.red
            : Colors.black,
      ),
    ),
    IconButton(
      icon: const Icon(Icons.arrow_right, size: 30),
      tooltip: 'Следующий день',
      onPressed: () {
        setState(() {
          _selectedDate = _selectedDate.add(const Duration(days: 1));
        });
        _loadAppointments();
      },
    ),
  ],
),




const SizedBox(height: 8),



// --- кнопки под календарём ---
const SizedBox(height: 8),
Row(
  children: [
    Expanded(
      child: ElevatedButton(
        onPressed: _goToday,
        child: const Text('Сегодня'),
      ),
    ),
    const SizedBox(width: 8),
    Expanded(
      child: ElevatedButton(
        onPressed: _resetFilter,
        child: const Text('Сброс'),
      ),
    ),
  ],
),

// --- Подсказка про воскресенье ---
const SizedBox(height: 4),
Text(
  'Воскресенье выделено красным',
  style: const TextStyle(fontSize: 12, color: Colors.grey),
),

                    if (_lastError != null) ...[
                      const SizedBox(height: 12),
                      Text('Ошибка: $_lastError', style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPatients.isEmpty
                    ? const Center(child: Text('На выбранную дату приёмов нет', style: TextStyle(fontSize: 16, color: Colors.black54)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _filteredPatients.length,
                        itemBuilder: (ctx, i) {
                          final p = _filteredPatients[i];
                          final fullName = p['fullName'] as String? ?? '';
                          final dob = p['dob'] as String? ?? '';
                          final phone = p['phone'] as String? ?? '';
                          final dt = p['appointment_datetime'] as String? ?? '';
                          final time = dt.contains(' ') ? dt.split(' ')[1].substring(0, 5) : '';
                          final count = _photoCounts[fullName] ?? 0;
                          final id = p['id'] is int ? p['id'] as int : int.tryParse('${p['id']}') ?? 0;

                          return Card(
  margin: const EdgeInsets.symmetric(vertical: 6),
  child: ListTile(
    title: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            fullName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Время приёма: $time',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.blueAccent,
          ),
        ),
      ],
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Дата рожд.: $dob'),
          Text('Телефон: $phone'),
        ],
      ),
    ),

							  
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: count > 0 ? Colors.green : Colors.red,
                                    child: count > 0 ? Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) : const Icon(Icons.remove, color: Colors.white),
                                  ),
                                  const SizedBox(width: 8),
								  
								  FutureBuilder<int>(
  future: ApiService.fetchConclusionCount(id),
  builder: (ctx, snap) {
    final c = snap.data ?? 0;
    final has = c > 0;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.description, color: has ? Colors.teal : Colors.grey),
          tooltip: has ? 'Заключений: $c' : 'Заключений нет',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DoctorConclusionPage(patientId: id,
  fullName: fullName, date: dateStr,)),
            );
          },
        ),
        if (has)
          Positioned(
            right: 6,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              child: Text('$c', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  },
),
const SizedBox(width: 8),
								  // 🔹 наша новая кнопка
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
          tooltip: 'Создать новый приём',
          onPressed: () => _createAppointmentForExisting(p),
        ),

        const SizedBox(width: 8),
								  
                                  IconButton(icon: const Icon(Icons.edit, size: 20), tooltip: 'Редактировать', onPressed: () => _showAddOrEditDialog(patient: p)),
                                  if (_isAdmin) ...[
                                    const SizedBox(width: 4),
                                    IconButton(icon: const Icon(Icons.delete, size: 20), tooltip: 'Удалить', onPressed: () => _confirmAndDelete(id)),
                                  ],
                                ],
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
          ),
        ],
      ),
    );
  }
}
