import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const App());

// ---------------------------------------------------------------- model

class Snap {
  final int followers, following, posts;
  Snap(this.followers, this.following, this.posts);
  Map<String, dynamic> toJson() => {'f': followers, 'g': following, 'p': posts};
  factory Snap.fromJson(Map<String, dynamic> j) =>
      Snap(j['f'] ?? 0, j['g'] ?? 0, j['p'] ?? 0);
}

class Account {
  final String username;
  final Map<String, Snap> history; // 'yyyy-MM-dd' -> snapshot
  String? error;
  Account(this.username, [Map<String, Snap>? h]) : history = h ?? {};

  Map<String, dynamic> toJson() => {
        'u': username,
        'h': history.map((k, v) => MapEntry(k, v.toJson())),
      };
  factory Account.fromJson(Map<String, dynamic> j) => Account(
        j['u'],
        (j['h'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, Snap.fromJson(v))),
      );

  List<String> get days => history.keys.toList()..sort();
  Snap? get latest => days.isEmpty ? null : history[days.last];

  /// Oxirgi [n] kundagi o'zgarish uchun taqqoslanadigan snapshot.
  MapEntry<String, Snap>? baseline(int n) {
    if (days.length < 2) return null;
    final limit = ymd(DateTime.now().subtract(Duration(days: n)));
    String pick = days.first;
    for (final d in days) {
      if (d.compareTo(limit) <= 0) pick = d;
    }
    if (pick == days.last) return null;
    return MapEntry(pick, history[pick]!);
  }

  int postsDelta(int n) {
    final b = baseline(n);
    return b == null ? 0 : (latest!.posts - b.value.posts).clamp(0, 1 << 30);
  }

  int followersDelta(int n) {
    final b = baseline(n);
    return b == null ? 0 : latest!.followers - b.value.followers;
  }

  /// Necha kundan beri yangi post yo'q; (kun, aniqmi)
  (int, bool) get idle {
    final d = days;
    if (d.isEmpty) return (0, false);
    String? lastUp;
    for (var i = 1; i < d.length; i++) {
      if (history[d[i]]!.posts > history[d[i - 1]]!.posts) lastUp = d[i];
    }
    final from = lastUp ?? d.first;
    return (DateTime.now().difference(DateTime.parse(from)).inDays, lastUp != null);
  }
}

String ymd(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------- fetch

const _ua =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

int _num(String s) {
  s = s.trim().replaceAll(',', '');
  final m = RegExp(r'^([\d.]+)\s*([KkMm]?)$').firstMatch(s);
  if (m == null) return int.tryParse(s) ?? 0;
  var v = double.tryParse(m.group(1)!) ?? 0;
  final suf = m.group(2)!.toLowerCase();
  if (suf == 'k') v *= 1e3;
  if (suf == 'm') v *= 1e6;
  return v.round();
}

Future<Snap> fetchStats(String user) async {
  // 1) JSON endpoint
  try {
    final r = await http.get(
      Uri.parse('https://www.instagram.com/api/v1/users/web_profile_info/?username=$user'),
      headers: {'x-ig-app-id': '936619743392459', 'User-Agent': _ua, 'Accept': '*/*'},
    ).timeout(const Duration(seconds: 20));
    if (r.statusCode == 200) {
      final u = jsonDecode(r.body)['data']['user'];
      return Snap(
        u['edge_followed_by']['count'],
        u['edge_follow']['count'],
        u['edge_owner_to_timeline_media']['count'],
      );
    }
  } catch (_) {}

  // 2) Zaxira: profil sahifasidagi og:description ("1,234 Followers, 5 Following, 78 Posts")
  final r = await http.get(
    Uri.parse('https://www.instagram.com/$user/'),
    headers: {'User-Agent': _ua, 'Accept-Language': 'en-US,en;q=0.9'},
  ).timeout(const Duration(seconds: 20));
  if (r.statusCode == 404) throw 'akkaunt topilmadi';
  final m = RegExp(
    r'([\d.,]+[KkMm]?)\s+Followers,\s+([\d.,]+[KkMm]?)\s+Following,\s+([\d.,]+[KkMm]?)\s+Posts',
  ).firstMatch(r.body);
  if (m == null) throw 'Instagram ma\'lumot bermadi (login so\'rayapti yoki bloklangan)';
  return Snap(_num(m.group(1)!), _num(m.group(2)!), _num(m.group(3)!));
}

// ---------------------------------------------------------------- app

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IG Tracker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true),
        darkTheme: ThemeData(
            colorSchemeSeed: Colors.pink, useMaterial3: true, brightness: Brightness.dark),
        home: const Home(),
      );
}

enum Sort { posts, growth, idle }

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<Account> accounts = [];
  Sort sort = Sort.posts;
  int range = 7;
  bool loading = false;
  String progress = '';
  DateTime? lastRun;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('accounts');
    if (raw != null) {
      accounts = (jsonDecode(raw) as List)
          .map((e) => Account.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final lr = p.getString('lastRun');
    if (lr != null) lastRun = DateTime.tryParse(lr);
    setState(() {});
    if (accounts.isNotEmpty &&
        (lastRun == null || DateTime.now().difference(lastRun!).inHours >= 6)) {
      refresh();
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('accounts', jsonEncode(accounts.map((a) => a.toJson()).toList()));
    if (lastRun != null) await p.setString('lastRun', lastRun!.toIso8601String());
  }

  Future<void> refresh() async {
    if (loading || accounts.isEmpty) return;
    setState(() => loading = true);
    final today = ymd(DateTime.now());
    for (var i = 0; i < accounts.length; i++) {
      final a = accounts[i];
      setState(() => progress = '${i + 1}/${accounts.length}  @${a.username}');
      try {
        a.history[today] = await fetchStats(a.username);
        a.error = null;
      } catch (e) {
        a.error = e.toString();
      }
      if (mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 1500));
    }
    lastRun = DateTime.now();
    await _save();
    if (mounted) setState(() {
      loading = false;
      progress = '';
    });
  }

  Future<void> _addDialog() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Akkaunt qo\'shish'),
        content: TextField(
          controller: c,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'username (bir nechtasini vergul yoki yangi qator bilan)',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Bekor')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Qo\'shish')),
        ],
      ),
    );
    if (text == null) return;
    final names = text
        .split(RegExp(r'[,\n; ]+'))
        .map((s) => s.trim().toLowerCase().replaceAll('@', '').split('instagram.com/').last.split('/').first.split('?').first)
        .where((s) => s.isNotEmpty)
        .toSet();
    for (final n in names) {
      if (!accounts.any((a) => a.username == n)) accounts.add(Account(n));
    }
    await _save();
    setState(() {});
    refresh();
  }

  Future<void> _remove(Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('@${a.username} o\'chirilsinmi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Yo\'q')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ha')),
        ],
      ),
    );
    if (ok == true) {
      accounts.remove(a);
      await _save();
      setState(() {});
    }
  }

  List<Account> get sorted {
    final l = [...accounts];
    switch (sort) {
      case Sort.posts:
        l.sort((a, b) => b.postsDelta(range).compareTo(a.postsDelta(range)));
      case Sort.growth:
        l.sort((a, b) => b.followersDelta(range).compareTo(a.followersDelta(range)));
      case Sort.idle:
        l.sort((a, b) => b.idle.$1.compareTo(a.idle.$1));
    }
    return l;
  }

  String _fmt(int n) {
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return (n < 0 ? '-' : '') + b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final list = sorted;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('IG Tracker'),
        actions: [
          IconButton(
            tooltip: 'Yangilash',
            onPressed: loading ? null : refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: const LinearProgressIndicator(),
              )
            : null,
      ),
      floatingActionButton:
          FloatingActionButton(onPressed: _addDialog, child: const Icon(Icons.add)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<Sort>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: Sort.posts, label: Text('Postlar')),
                      ButtonSegment(value: Sort.growth, label: Text('O\'sish')),
                      ButtonSegment(value: Sort.idle, label: Text('Jim')),
                    ],
                    selected: {sort},
                    onSelectionChanged: (s) => setState(() => sort = s.first),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: range,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 kun')),
                    DropdownMenuItem(value: 7, child: Text('7 kun')),
                    DropdownMenuItem(value: 30, child: Text('30 kun')),
                  ],
                  onChanged: (v) => setState(() => range = v ?? 7),
                ),
              ],
            ),
          ),
          if (progress.isNotEmpty)
            Padding(padding: const EdgeInsets.all(6), child: Text(progress)),
          Expanded(
            child: accounts.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Akkaunt yo\'q.\n+ tugmasini bosib 9 ta akkaunt usernamesini kiriting.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: refresh,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final a = list[i];
                        final s = a.latest;
                        final (idleDays, exact) = a.idle;
                        final pd = a.postsDelta(range);
                        final fd = a.followersDelta(range);
                        final quiet = s != null && a.days.length > 1 && idleDays >= 3;
                        return Card(
                          child: ListTile(
                            onLongPress: () => _remove(a),
                            leading: CircleAvatar(
                              backgroundColor: i == 0 && accounts.length > 1 && s != null
                                  ? cs.primary
                                  : cs.surfaceContainerHighest,
                              foregroundColor:
                                  i == 0 && accounts.length > 1 && s != null ? cs.onPrimary : cs.onSurface,
                              child: Text('${i + 1}'),
                            ),
                            title: Text('@${a.username}'),
                            subtitle: s == null
                                ? Text(a.error ?? 'Yuklanmoqda...',
                                    style: TextStyle(color: a.error != null ? cs.error : null))
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('👥 ${_fmt(s.followers)}   ${fd >= 0 ? '+' : ''}$fd   ·   📷 ${_fmt(s.posts)} post'),
                                      Text(
                                        a.days.length < 2
                                            ? 'Tarix hali yo\'q (ertaga solishtiriladi)'
                                            : '$range kunda: $pd ta post',
                                      ),
                                      if (a.error != null)
                                        Text('⚠ ${a.error}', style: TextStyle(color: cs.error)),
                                    ],
                                  ),
                            trailing: s == null || a.days.length < 2
                                ? null
                                : Chip(
                                    label: Text(quiet ? 'Jim ${idleDays}${exact ? '' : '+'} k' : 'Faol'),
                                    backgroundColor: quiet ? cs.errorContainer : cs.secondaryContainer,
                                    visualDensity: VisualDensity.compact,
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
