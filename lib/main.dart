import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const QuitingApp());

class QuitingApp extends StatefulWidget {
  const QuitingApp({super.key});
  @override State<QuitingApp> createState() => _QuitingAppState();
}

class _QuitingAppState extends State<QuitingApp> {
  ThemeMode mode = ThemeMode.system;
  String style = 'liquid';
  String accent = 'blue';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      style = p.getString('style') ?? 'liquid';
      accent = p.getString('accent') ?? 'blue';
      final m = p.getString('mode') ?? 'system';
      mode = m == 'light' ? ThemeMode.light : m == 'dark' ? ThemeMode.dark : ThemeMode.system;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('style', style);
    await p.setString('accent', accent);
    await p.setString('mode', mode == ThemeMode.light ? 'light' : mode == ThemeMode.dark ? 'dark' : 'system');
  }

  Color get seed => accent == 'green' ? Colors.green : Colors.blue;

  ThemeData _theme(Brightness b) => ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: b),
    scaffoldBackgroundColor: b == Brightness.dark ? const Color(0xFF080B10) : const Color(0xFFF4F6F8),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Quiting',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: mode,
      home: HomePage(style: style, onSettings: () async {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => SettingsPage(
            style: style, accent: accent, mode: mode,
            onChanged: (s, a, m) {
              setState(() { style = s; accent = a; mode = m; });
              _save();
            },
          ),
        ));
      }),
    );
  }
}

class HomePage extends StatefulWidget {
  final String style;
  final VoidCallback onSettings;
  const HomePage({super.key, required this.style, required this.onSettings});

  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool connected = false;
  int tab = 0;
  final profiles = ['My VPN', 'Home Server'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiting', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(onPressed: widget.onSettings, icon: const Icon(Icons.settings_rounded))],
      ),
      body: tab == 0 ? _home() : _profiles(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'VPN'),
          NavigationDestination(icon: Icon(Icons.dns_outlined), selectedIcon: Icon(Icons.dns), label: 'Конфиги'),
        ],
      ),
    );
  }

  Widget _home() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _glass(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Icon(
                connected ? Icons.shield : Icons.shield_outlined,
                size: 82,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(connected ? 'Подключено' : 'Отключено',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(connected ? 'Quiting защищает соединение' : 'Выберите конфиг и подключитесь',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => setState(() => connected = !connected),
                icon: Icon(connected ? Icons.power_settings_new : Icons.play_arrow_rounded),
                label: Text(connected ? 'Отключиться' : 'Подключиться'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.tune_rounded),
                label: Text(profiles.first),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _stat('Скорость', connected ? '—' : '0 KB/s', Icons.speed)),
          const SizedBox(width: 12),
          Expanded(child: _stat('Трафик', connected ? '—' : '0 MB', Icons.data_usage)),
        ]),
      ],
    );
  }

  Widget _profiles() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Конфигурации', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        ...profiles.map((p) => Card(
          child: ListTile(
            leading: const Icon(Icons.dns_rounded),
            title: Text(p, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('sing-box / VPN профиль'),
            trailing: const Icon(Icons.chevron_right),
          ),
        )),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('Добавить конфиг')),
        OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.qr_code_scanner), label: const Text('Импорт QR')),
      ],
    );
  }

  Widget _stat(String title, String value, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      ]),
    ),
  );

  Widget _glass({required Widget child}) {
    if (widget.style != 'liquid') return Card(child: Padding(padding: const EdgeInsets.all(22), child: child));
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: Theme.of(context).colorScheme.surface.withOpacity(.48),
            border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(.10)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final String style, accent;
  final ThemeMode mode;
  final void Function(String, String, ThemeMode) onChanged;

  const SettingsPage({
    super.key, required this.style, required this.accent, required this.mode, required this.onChanged
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('Стиль интерфейса', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'liquid', label: Text('Liquid Glass'), icon: Icon(Icons.blur_on)),
              ButtonSegment(value: 'material', label: Text('Material You'), icon: Icon(Icons.widgets)),
            ],
            selected: {style},
            onSelectionChanged: (v) => onChanged(v.first, accent, mode),
          ),
          const SizedBox(height: 28),
          const Text('Тема', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 10),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('Система')),
              ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная')),
            ],
            selected: {mode},
            onSelectionChanged: (v) => onChanged(style, accent, v.first),
          ),
          const SizedBox(height: 28),
          const Text('Акцент', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'blue', label: Text('Синий'), icon: Icon(Icons.circle)),
              ButtonSegment(value: 'green', label: Text('Зелёный'), icon: Icon(Icons.circle)),
            ],
            selected: {accent},
            onSelectionChanged: (v) => onChanged(style, v.first, mode),
          ),
        ],
      ),
    );
  }
}
