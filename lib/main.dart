import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sing_box/sing_box.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SingBox.instance.initialize(const SingBoxOptions(
    android: SingBoxAndroidOptions(
      notificationTitle: 'Quiting VPN',
      showTrafficInNotification: true,
      stopActionTitle: 'Отключить',
    ),
    logMaxLines: 2000,
  ));
  runApp(const QuitingApp());
}

class Profile {
  final String id;
  String name;
  String config;

  Profile({required this.id, required this.name, required this.config});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'config': config};

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        name: json['name'] as String,
        config: json['config'] as String,
      );
}

class QuitingApp extends StatefulWidget {
  const QuitingApp({super.key});

  @override
  State<QuitingApp> createState() => _QuitingAppState();
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
    if (!mounted) return;
    setState(() {
      style = p.getString('style') ?? 'liquid';
      accent = p.getString('accent') ?? 'blue';
      final m = p.getString('mode') ?? 'system';
      mode = m == 'light'
          ? ThemeMode.light
          : m == 'dark'
              ? ThemeMode.dark
              : ThemeMode.system;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('style', style);
    await p.setString('accent', accent);
    await p.setString(
      'mode',
      mode == ThemeMode.light
          ? 'light'
          : mode == ThemeMode.dark
              ? 'dark'
              : 'system',
    );
  }

  ThemeData _theme(Brightness brightness) {
    final seed = accent == 'green' ? Colors.green : Colors.blue;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF080B10)
          : const Color(0xFFF4F6F8),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Quiting',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: mode,
      home: HomePage(
        style: style,
        onSettings: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SettingsPage(
                style: style,
                accent: accent,
                mode: mode,
                onChanged: (s, a, m) {
                  setState(() {
                    style = s;
                    accent = a;
                    mode = m;
                  });
                  _save();
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String style;
  final VoidCallback onSettings;

  const HomePage({super.key, required this.style, required this.onSettings});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  final List<Profile> profiles = [];
  String? selectedId;
  bool busy = false;
  String? error;
  double downloadSpeed = 0;
  double uploadSpeed = 0;
  int downloadTotal = 0;
  int uploadTotal = 0;
  StreamSubscription<SingBoxConnectionStatus>? _statusSub;
  StreamSubscription<SingBoxConnectionStats>? _statsSub;
  SingBoxConnectionStatus status = SingBox.instance.status;

  bool get connected => status == SingBoxConnectionStatus.connected;
  bool get connecting => status == SingBoxConnectionStatus.connecting ||
      status == SingBoxConnectionStatus.disconnecting;
  Profile? get selected {
    for (final p in profiles) {
      if (p.id == selectedId) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _statusSub = SingBox.instance.watchConnectionStatus().listen((value) {
      if (!mounted) return;
      setState(() => status = value);
    });
    _statsSub = SingBox.instance.watchConnectionStats().listen((value) {
      if (!mounted) return;
      setState(() {
        downloadSpeed = value.downloadSpeed.toDouble();
        uploadSpeed = value.uploadSpeed.toDouble();
        downloadTotal = value.downloadTotal;
        uploadTotal = value.uploadTotal;
      });
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _statsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('profiles') ?? <String>[];
    final loaded = <Profile>[];
    for (final item in raw) {
      try {
        loaded.add(Profile.fromJson(jsonDecode(item) as Map<String, dynamic>));
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      profiles
        ..clear()
        ..addAll(loaded);
      selectedId = p.getString('selected_profile');
      if (selectedId == null && profiles.isNotEmpty) selectedId = profiles.first.id;
    });
  }

  Future<void> _saveProfiles() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('profiles', profiles.map((x) => jsonEncode(x.toJson())).toList());
    if (selectedId == null) {
      await p.remove('selected_profile');
    } else {
      await p.setString('selected_profile', selectedId!);
    }
  }

  Future<void> _connect() async {
    final profile = selected;
    if (profile == null) {
      _show('Сначала добавь конфигурацию.');
      setState(() => tab = 1);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await SingBox.instance.connect(profile.config);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = _cleanError(e));
      _show(_cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await SingBox.instance.disconnect();
    } catch (e) {
      if (mounted) {
        setState(() => error = _cleanError(e));
        _show(_cleanError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _cleanError(Object e) {
    final text = e.toString();
    return text.replaceFirst(RegExp(r'^.*?: '), '');
  }

  Future<void> _addFromText(String text, {String? suggestedName}) async {
    final value = text.trim();
    if (value.isEmpty) return;
    try {
      await SingBox.instance.checkConfig(value);
    } catch (e) {
      _show('Конфигурация не прошла проверку:\n${_cleanError(e)}');
      return;
    }
    final name = suggestedName ?? _nameFromConfig(value);
    final profile = Profile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      config: value,
    );
    setState(() {
      profiles.add(profile);
      selectedId = profile.id;
    });
    await _saveProfiles();
    _show('Конфигурация добавлена.');
  }

  String _nameFromConfig(String value) {
    final first = value.split(RegExp(r'[\r\n]')).first.trim();
    final hash = first.indexOf('#');
    if (hash >= 0 && hash < first.length - 1) {
      final name = Uri.decodeComponent(first.substring(hash + 1)).trim();
      if (name.isNotEmpty) return name;
    }
    if (value.startsWith('{')) return 'JSON config';
    final scheme = value.split(':').first.toUpperCase();
    return scheme.isEmpty ? 'VPN config' : scheme;
  }

  Future<void> _addFromFile() async {
    final file = await FilePicker.pickFile();
if (file == null) return;
    if (files.isEmpty) return;
    final file = files.single;
    String text;
    try {
      final bytes = await file.readAsBytes();
      text = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      if (file.path == null) {
        _show('Не удалось прочитать файл.');
        return;
      }
      text = await File(file.path!).readAsString();
    }
    await _addFromText(
      text,
      suggestedName: file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
    );
  }

  Future<void> _addManual() async {
    final controller = TextEditingController();
    final nameController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить конфиг'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Ссылка или JSON',
                  hintText: 'vless://... или JSON sing-box',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              await _addFromText(
                controller.text,
                suggestedName: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
              );
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    controller.dispose();
    nameController.dispose();
    if (result == true && mounted) setState(() {});
  }

  Future<void> _scanQr() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrPage()),
    );
    if (value != null && value.trim().isNotEmpty) await _addFromText(value);
  }

  Future<void> _rename(Profile profile) async {
    final controller = TextEditingController(text: profile.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      setState(() => profile.name = controller.text.trim());
      await _saveProfiles();
    }
    controller.dispose();
  }

  Future<void> _delete(Profile profile) async {
    if (connected && selectedId == profile.id) await _disconnect();
    setState(() {
      profiles.removeWhere((p) => p.id == profile.id);
      if (selectedId == profile.id) selectedId = profiles.isEmpty ? null : profiles.first.id;
    });
    await _saveProfiles();
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

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
    final selectedName = selected?.name ?? 'Нет выбранного конфига';
    final down = _speed(downloadSpeed);
    final up = _speed(uploadSpeed);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _glass(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Icon(connected ? Icons.shield : Icons.shield_outlined, size: 82,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                connected ? 'Подключено' : connecting ? 'Подключение…' : 'Отключено',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                error ?? selectedName,
                textAlign: TextAlign.center,
                style: TextStyle(color: error != null
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: busy || connecting ? null : connected ? _disconnect : _connect,
                icon: Icon(connected ? Icons.power_settings_new : Icons.play_arrow_rounded),
                label: Text(connected ? 'Отключиться' : 'Подключиться'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => setState(() => tab = 1),
                icon: const Icon(Icons.tune_rounded),
                label: Text(selectedName),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _stat('↓ Скорость', down, Icons.download_rounded)),
          const SizedBox(width: 12),
          Expanded(child: _stat('↑ Скорость', up, Icons.upload_rounded)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _stat('↓ Трафик', _bytes(downloadTotal), Icons.south_rounded)),
          const SizedBox(width: 12),
          Expanded(child: _stat('↑ Трафик', _bytes(uploadTotal), Icons.north_rounded)),
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
        if (profiles.isEmpty)
          Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: const [
            Icon(Icons.dns_outlined, size: 48),
            SizedBox(height: 10),
            Text('Конфигов пока нет', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 5),
            Text('Добавь ссылку, JSON, файл или QR-код.'),
          ])))
        else
          ...profiles.map((p) => Card(
                child: ListTile(
                  onTap: () async {
                    setState(() => selectedId = p.id);
                    await _saveProfiles();
                  },
                  leading: CircleAvatar(child: Icon(selectedId == p.id ? Icons.check : Icons.dns_rounded)),
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(_typeOf(p.config)),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'rename') _rename(p);
                      if (v == 'delete') _delete(p);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                      PopupMenuItem(value: 'delete', child: Text('Удалить')),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _addManual, icon: const Icon(Icons.add), label: const Text('Добавить конфиг вручную')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _addFromFile, icon: const Icon(Icons.file_open), label: const Text('Импорт файла')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _scanQr, icon: const Icon(Icons.qr_code_scanner), label: const Text('Импорт QR')),
      ],
    );
  }

  Widget _stat(String title, String value, IconData icon) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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

  String _typeOf(String config) {
    if (config.trimLeft().startsWith('{')) return 'JSON / sing-box';
    final scheme = config.split(':').first.toUpperCase();
    return '$scheme / sing-box';
  }

  String _speed(double value) {
    if (value < 1024) return '${value.round()} B/s';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB/s';
    return '${(value / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }

  String _bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(value / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class QrPage extends StatefulWidget {
  const QrPage({super.key});

  @override
  State<QrPage> createState() => _QrPageState();
}

class _QrPageState extends State<QrPage> {
  bool done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сканировать QR')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (done) return;
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null && value.trim().isNotEmpty) {
                  done = true;
                  Navigator.pop(context, value.trim());
                  break;
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 42,
            child: Text(
              'Наведите камеру на QR-код конфигурации',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final String style, accent;
  final ThemeMode mode;
  final void Function(String, String, ThemeMode) onChanged;

  const SettingsPage({
    super.key,
    required this.style,
    required this.accent,
    required this.mode,
    required this.onChanged,
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
