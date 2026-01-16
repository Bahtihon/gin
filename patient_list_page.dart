import 'settings_page.dart';
// …
AppBar(
  title: Text('Приёмы на сегодня'),
  actions: [
    IconButton(
      icon: Icon(Icons.settings),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SettingsPage()),
      ),
    )
  ],
),
