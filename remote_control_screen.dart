class RemoteControlScreen extends StatelessWidget {
  final String ip;
  final int port;
  const RemoteControlScreen({
    required this.ip,
    required this.port,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // TODO: сделали инициализацию scrcpy-over-WebRTC по ip и port
    return Scaffold(
      appBar: AppBar(title: Text('Управление $ip:$port')),
      body: /* ваш WebRTC-view */,
    );
  }
}
