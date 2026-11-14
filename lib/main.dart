import 'dart:async';
import 'dart:convert';
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
      stopActionTitle: 'Disconnect',
    ),
  ));
  runApp(const QuitingApp());
}

class VpnProfile {
  final String id;
  final String name;
  final String source;

  const VpnProfile({required this.id, required this.name, required this.source});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'source': source};
  factory VpnProfile.fromJson(Map<String, dynamic> json) => VpnProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        source: json['source'] as String,
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
      home: HomePage(
        style: style,
        onSettings: () async {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => SettingsPage(
              style: style,
              accent: accent,
              mode: mode,
              onChanged: (s, a, m) {
                setState(() { style = s; accent = a; mode = m; });
                _save();
              },
            ),
          ));
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
  List<VpnProfile> profiles = [];
  String? activeId;
  StreamSubscription<SingBoxConnectionStatus>? statusSub;
  StreamSubscription<SingBoxConnectionState>? stateSub;
  StreamSubscription<SingBoxConnectionStats>? statsSub;
  SingBoxConnectionStatus status = SingBox.instance.status;
  SingBoxConnectionStats? stats;
  String? error;

  bool get connected => status == SingBoxConnectionStatus.connected || status == SingBoxConnectionStatus.connecting;
  VpnProfile? get active => profiles.where((p) => p.id == activeId).isEmpty ? null : profiles.firstWhere((p) => p.id == activeId);

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    statusSub = SingBox.instance.watchConnectionStatus().listen((s) {
      if (mounted) setState(() => status = s);
    });
    stateSub = SingBox.instance.watchConnectionState().listen((s) {
      if (mounted && s.error != null) setState(() => error = s.error);
    });
    statsSub = SingBox.instance.watchConnectionStats().listen((s) {
      if (mounted) setState(() => stats = s);
    });
  }

  @override
  void dispose() {
    statusSub?.cancel();
    stateSub?.cancel();
    statsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('profiles');
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).map((e) => VpnProfile.fromJson(Map<String, dynamic>.from(e))).toList();
        if (mounted) setState(() { profiles = list; activeId = p.getString('activeId') ?? list.firstOrNull?.id; });
        return;
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveProfiles() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('profiles', jsonEncode(profiles.map((e) => e.toJson()).toList()));
    if (activeId == null) {
      await p.remove('activeId');
    } else {
      await p.setString('activeId', activeId!);
    }
  }

  Future<void> _connect() async {
    final profile = active;
    if (profile == null) {
      _show('Сначала добавь конфигурацию.');
      setState(() => tab = 1);
      return;
    }
    setState(() { error = null; });
    try {
      if (SingBox.instance.status.isActive) {
        await SingBox.instance.disconnect();
      } else {
        await SingBox.instance.connect(profile.source);
      }
    } on SingBoxException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _pickConfig() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json', 'txt', 'conf']);
    if (file == null) return;
    try {
      final source = utf8.decode(await file.readAsBytes()).trim();
      await _addProfile(source, file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''));
    } catch (e) {
      _show('Не удалось прочитать конфиг: $e');
    }
  }

  Future<void> _addFromText() async {
    final controller = TextEditingController();
    final nameController = TextEditingController(text: 'Новый конфиг');
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Добавить конфиг'),
        content: SizedBox(width: 600, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Название')),
          const SizedBox(height: 12),
          TextField(controller: controller, minLines: 5, maxLines: 10, decoration: const InputDecoration(labelText: 'VLESS / VMess / Trojan / SS / JSON', border: OutlineInputBorder())),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Добавить')),
        ],
      ),
    );
    if (result == true) {
      final source = controller.text.trim();
      if (source.isEmpty) return;
      await _addProfile(source, nameController.text.trim().isEmpty ? 'Новый конфиг' : nameController.text.trim());
    }
    controller.dispose();
    nameController.dispose();
  }

  Future<void> _scanQr() async {
    final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const QrScannerPage()));
    if (result == null || result.trim().isEmpty) return;
    await _addProfile(result.trim(), 'QR конфиг');
  }

  Future<void> _addProfile(String source, String name) async {
    try {
      await SingBox.instance.checkConfig(source);
      final profile = VpnProfile(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name, source: source);
      setState(() { profiles = [...profiles, profile]; activeId = profile.id; error = null; });
      await _saveProfiles();
      _show('Конфиг добавлен.');
    } on SingBoxException catch (e) {
      _show('Конфиг не прошёл проверку:\n${e.message}');
    } catch (e) {
      _show('Ошибка проверки: $e');
    }
  }

  Future<void> _deleteProfile(VpnProfile profile) async {
    if (SingBox.instance.status.isActive && activeId == profile.id) await SingBox.instance.disconnect();
    setState(() {
      profiles = profiles.where((p) => p.id != profile.id).toList();
      if (activeId == profile.id) activeId = profiles.isEmpty ? null : profiles.first.id;
    });
    await _saveProfiles();
  }

  Future<void> _renameProfile(VpnProfile profile) async {
    final c = TextEditingController(text: profile.name);
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Переименовать'),
      content: TextField(controller: c, autofocus: true),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить'))],
    ));
    if (ok == true && c.text.trim().isNotEmpty) {
      setState(() { profiles = profiles.map((p) => p.id == profile.id ? VpnProfile(id: p.id, name: c.text.trim(), source: p.source) : p).toList(); });
      await _saveProfiles();
    }
    c.dispose();
  }

  void _show(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String _speed(int? bytes) {
    if (bytes == null) return '0 B/s';
    if (bytes < 1024) return '$bytes B/s';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiting', style: TextStyle(fontWeight: FontWeight.w800)), actions: [IconButton(onPressed: widget.onSettings, icon: const Icon(Icons.settings_rounded))]),
      body: tab == 0 ? _home() : _profiles(),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
        NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'VPN'),
        NavigationDestination(icon: Icon(Icons.dns_outlined), selectedIcon: Icon(Icons.dns), label: 'Конфиги'),
      ]),
    );
  }

  Widget _home() {
    final s = stats;
    return ListView(padding: const EdgeInsets.all(18), children: [
      _glass(child: Column(children: [
        const SizedBox(height: 12),
        Icon(connected ? Icons.shield : Icons.shield_outlined, size: 82, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(status == SingBoxConnectionStatus.connecting ? 'Подключение…' : connected ? 'Подключено' : 'Отключено', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(active?.name ?? 'Конфиг не выбран', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: status == SingBoxConnectionStatus.connecting ? null : _connect, icon: Icon(connected ? Icons.power_settings_new : Icons.play_arrow_rounded), label: Text(connected ? 'Отключиться' : 'Подключиться'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54))),
        const SizedBox(height: 14),
        OutlinedButton.icon(onPressed: () => setState(() => tab = 1), icon: const Icon(Icons.tune_rounded), label: Text(active?.name ?? 'Выбрать конфиг'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
        if (error != null) ...[
          const SizedBox(height: 14),
          Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(14)), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer))),
        ],
      ])),
      const SizedBox(height: 16),
      Row(children: [Expanded(child: _stat('Скачивание', _speed(s?.downloadSpeed), Icons.download_rounded)), const SizedBox(width: 12), Expanded(child: _stat('Отдача', _speed(s?.uploadSpeed), Icons.upload_rounded))]),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: _stat('Трафик ↓', _bytes(s?.downloadTotal), Icons.south_rounded)), const SizedBox(width: 12), Expanded(child: _stat('Трафик ↑', _bytes(s?.uploadTotal), Icons.north_rounded))]),
    ]);
  }

  String _bytes(int? value) {
    if (value == null) return '0 B';
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(value / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  Widget _profiles() => ListView(padding: const EdgeInsets.all(18), children: [
    Text('Конфигурации', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: 14),
    if (profiles.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('Пока нет конфигураций. Добавь ссылку, JSON-файл или QR.'))),
    ...profiles.map((p) => Card(child: ListTile(
      onTap: () async { setState(() => activeId = p.id); await _saveProfiles(); },
      leading: Icon(p.id == activeId ? Icons.radio_button_checked : Icons.radio_button_off, color: p.id == activeId ? Theme.of(context).colorScheme.primary : null),
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(p.source.startsWith('{') ? 'sing-box JSON' : 'Share link'),
      trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'rename') _renameProfile(p); if (v == 'delete') _deleteProfile(p); }, itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Переименовать')), PopupMenuItem(value: 'delete', child: Text('Удалить'))]),
    ))),
    const SizedBox(height: 8),
    FilledButton.icon(onPressed: _addFromText, icon: const Icon(Icons.link_rounded), label: const Text('Добавить ссылку / JSON')),
    OutlinedButton.icon(onPressed: _pickConfig, icon: const Icon(Icons.file_open_rounded), label: const Text('Импорт файла')),
    OutlinedButton.icon(onPressed: _scanQr, icon: const Icon(Icons.qr_code_scanner), label: const Text('Импорт QR')),
  ]);

  Widget _stat(String title, String value, IconData icon) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 12), Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)), Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))])));

  Widget _glass({required Widget child}) {
    if (widget.style != 'liquid') return Card(child: Padding(padding: const EdgeInsets.all(22), child: child));
    return ClipRRect(borderRadius: BorderRadius.circular(30), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22), child: Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), color: Theme.of(context).colorScheme.surface.withOpacity(.48), border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(.10))), child: child)));
  }
}

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});
  @override State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final controller = MobileScannerController();
  bool done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Сканировать QR')),
    body: Stack(fit: StackFit.expand, children: [
      MobileScanner(controller: controller, onDetect: (capture) {
        if (done) return;
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null && value.trim().isNotEmpty) { done = true; controller.stop(); Navigator.pop(context, value); break; }
        }
      }),
      Center(child: Container(width: 270, height: 270, decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(24)))),
    ]),
  );
}

class SettingsPage extends StatelessWidget {
  final String style, accent;
  final ThemeMode mode;
  final void Function(String, String, ThemeMode) onChanged;
  const SettingsPage({super.key, required this.style, required this.accent, required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Настройки')), body: ListView(padding: const EdgeInsets.all(18), children: [
    const Text('Стиль интерфейса', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), const SizedBox(height: 10),
    SegmentedButton<String>(segments: const [ButtonSegment(value: 'liquid', label: Text('Liquid Glass'), icon: Icon(Icons.blur_on)), ButtonSegment(value: 'material', label: Text('Material You'), icon: Icon(Icons.widgets))], selected: {style}, onSelectionChanged: (v) => onChanged(v.first, accent, mode)),
    const SizedBox(height: 28), const Text('Тема', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), const SizedBox(height: 10),
    SegmentedButton<ThemeMode>(segments: const [ButtonSegment(value: ThemeMode.system, label: Text('Система')), ButtonSegment(value: ThemeMode.light, label: Text('Светлая')), ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная'))], selected: {mode}, onSelectionChanged: (v) => onChanged(style, accent, v.first)),
    const SizedBox(height: 28), const Text('Акцент', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), const SizedBox(height: 10),
    SegmentedButton<String>(segments: const [ButtonSegment(value: 'blue', label: Text('Синий'), icon: Icon(Icons.circle)), ButtonSegment(value: 'green', label: Text('Зелёный'), icon: Icon(Icons.circle))], selected: {accent}, onSelectionChanged: (v) => onChanged(style, v.first, mode)),
  ]);
}

extension FirstOrNull<T> on List<T> { T? get firstOrNull => isEmpty ? null : first; }
