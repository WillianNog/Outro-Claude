import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const FlexaoApp());

class FlexaoApp extends StatelessWidget {
  const FlexaoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xfff5f7f3),
          textTheme: GoogleFonts.interTextTheme(),
          colorScheme: const ColorScheme.light(
            primary: Color(0xff5d8f16),
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        home: const WelcomeScreen(),
      );
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _name = TextEditingController(text: 'Willian');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _continue() {
    final name = _name.text.trim().isEmpty ? 'Você' : _name.text.trim();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(userName: name)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xff5d8f16),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.fitness_center_rounded, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 28),
              const Text('Sua meta,\nseu grupo.', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, height: 1.05)),
              const SizedBox(height: 14),
              const Text('Registre suas flexões e acompanhe a evolução de todos até o fim do ano.', style: TextStyle(color: Color(0xff657064), fontSize: 16, height: 1.4)),
              const SizedBox(height: 34),
              TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: _input('Como podemos te chamar?')),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _continue, icon: const Icon(Icons.g_mobiledata_rounded, size: 28), label: const Text('Continuar com Google'), style: _fullButton()),
              const SizedBox(height: 12),
              Center(child: TextButton(onPressed: _continue, child: const Text('Continuar por enquanto sem login'))),
              const Spacer(),
              const Center(child: Text('Flexão 3000 - desafio entre amigos', style: TextStyle(color: Color(0xff657064), fontSize: 12))),
            ]),
          ),
        ),
      );
}

InputDecoration _input(String label) => InputDecoration(labelText: label, filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none));
ButtonStyle _fullButton() => FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)));

class Player {
  const Player(this.name, this.today, this.color);
  final String name;
  final int today;
  final Color color;
}

enum _Period { semana, mes, ano }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.userName});
  final String userName;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _goal = 3000;
  static const _storageKey = 'dailyPushupsV2';
  static const _inviteCode = 'FLEX-2026';
  Map<String, int> _daily = {};
  int _tab = 0;
  bool _loading = true;
  _Period _historyPeriod = _Period.semana;

  String get _todayKey => _key(DateTime.now());
  int get _today => _daily[_todayKey] ?? 0;
  int get _total => _daily.values.fold(0, (sum, item) => sum + item);
  int get _daysLeft { final now = DateTime.now(); return DateTime(now.year, 12, 31).difference(DateTime(now.year, now.month, now.day)).inDays + 1; }
  List<Player> get _players => [Player(widget.userName, _today, const Color(0xffb7ff4a)), const Player('Seu amigo', 29, Color(0xff8db8ff))];

  int get _streak {
    var day = DateTime.now();
    if ((_daily[_key(day)] ?? 0) == 0) day = day.subtract(const Duration(days: 1));
    var streak = 0;
    while ((_daily[_key(day)] ?? 0) > 0) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  String get _streakMedal => _streak >= 100 ? '🏆' : _streak >= 30 ? '🥇' : _streak >= 7 ? '🥈' : _streak >= 3 ? '🥉' : '⚡';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _daily = decoded.map((key, value) => MapEntry(key, value as int));
    } else {
      _daily[_todayKey] = 25;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_daily));
  }

  void _add(int amount) {
    setState(() => _daily[_todayKey] = _today + amount);
    _save();
  }

  void _undo() {
    if (_today == 0) return;
    setState(() => _daily[_todayKey] = _today - 1);
    _save();
  }

  DateTime _parseKey(String key) {
    final parts = key.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  int _periodTotal(_Period period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = switch (period) {
      _Period.semana => today.subtract(const Duration(days: 6)),
      _Period.mes => DateTime(today.year, today.month, 1),
      _Period.ano => DateTime(today.year, 1, 1),
    };
    return _daily.entries.where((entry) => !_parseKey(entry.key).isBefore(from)).fold(0, (sum, entry) => sum + entry.value);
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: now, firstDate: DateTime(now.year, 1, 1), lastDate: now);
    if (picked != null) _editDay(picked);
  }

  Future<void> _editDay(DateTime day) async {
    final controller = TextEditingController(text: '${_daily[_key(day)] ?? 0}');
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Editar ${day.day}/${day.month}/${day.year}'),
        content: TextField(controller: controller, keyboardType: TextInputType.number, autofocus: true, decoration: _input('Quantidade de flexões')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, 0), child: const Text('Remover')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, int.tryParse(controller.text) ?? 0), child: const Text('Salvar')),
        ],
      ),
    );
    if (result == null) return;
    setState(() {
      if (result <= 0) {
        _daily.remove(_key(day));
      } else {
        _daily[_key(day)] = result;
      }
    });
    _save();
  }

  void _shareInvite() {
    SharePlus.instance.share(ShareParams(text: 'Bora somar flexões comigo! Entre no meu grupo do Flexão 3000 com o código $_inviteCode.'));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final pages = [_dashboard(), _ranking(), _history(), _group()];
    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Ranking'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Histórico'),
          NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group), label: 'Grupo'),
        ],
      ),
    );
  }

  Widget _shell(String title, Widget child, {String? badge}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800))), if (badge != null) _pill(badge)]),
          const SizedBox(height: 20),
          Expanded(child: child),
        ]),
      );

  Widget _dashboard() => _shell('Olá, ${widget.userName}', ListView(children: [
        Text('DESAFIO 2026', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
        const SizedBox(height: 10),
        _goalCard(),
        const SizedBox(height: 16),
        _streakCard(),
        const Text('Adicionar flexões', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        const SizedBox(height: 12),
        Row(children: [1, 5, 10].map((amount) => Expanded(child: Padding(padding: EdgeInsets.only(right: amount == 10 ? 0 : 10), child: FilledButton(onPressed: () => _add(amount), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 17), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: Text('+$amount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)))))).toList()),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: _today == 0 ? null : _undo, icon: const Icon(Icons.undo), label: const Text('Desfazer 1 flexão'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
        const SizedBox(height: 20),
        _todayCard(),
      ]), badge: '🔥 $_today hoje');

  Widget _goalCard() {
    final progress = (_total / _goal).clamp(0.0, 1.0);
    return Container(padding: const EdgeInsets.all(22), decoration: _card(radius: 28, shadow: true), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$_total', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 52, fontWeight: FontWeight.w800, height: 1)),
      const SizedBox(height: 4), const Text('de 3.000 flexões', style: TextStyle(color: Color(0xff657064), fontSize: 16)),
      const SizedBox(height: 20), ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: progress, minHeight: 12, backgroundColor: const Color(0xffe3e8df))),
      const SizedBox(height: 14), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('${_goal - _total} faltam', style: const TextStyle(fontWeight: FontWeight.w700)), Text('$_daysLeft dias até 31 dez', style: const TextStyle(color: Color(0xff657064)))]),
    ]));
  }

  Widget _streakCard() {
    if (_streak == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: _card(radius: 18),
      child: Row(children: [
        Text(_streakMedal, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(child: Text('$_streak ${_streak == 1 ? 'dia seguido' : 'dias seguidos'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
      ]),
    );
  }

  Widget _todayCard() => Container(padding: const EdgeInsets.all(18), decoration: _card(), child: Row(children: [
        const Icon(Icons.calendar_today_outlined, color: Color(0xff5d8f16)), const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Hoje', style: TextStyle(fontWeight: FontWeight.w700)), Text('Seu registro fica salvo neste celular.', style: TextStyle(color: Color(0xff657064)))])),
        Text('$_today', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      ]));

  Widget _ranking() {
    final players = [..._players]..sort((a, b) => b.today.compareTo(a.today));
    return _shell('Ranking', ListView(children: [
      const Text('HOJE', style: TextStyle(color: Color(0xff5d8f16), letterSpacing: 1.5, fontWeight: FontWeight.w800)), const SizedBox(height: 14),
      ...players.asMap().entries.map((entry) => _rankItem(entry.key + 1, entry.value)),
      const SizedBox(height: 18), const Text('Na versão online, este ranking será atualizado para todos do grupo em tempo real.', style: TextStyle(color: Color(0xff657064))),
    ]), badge: '2 pessoas');
  }

  Widget _rankItem(int rank, Player player) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16), decoration: _card(), child: Row(children: [
        Text('$rank.', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(width: 14), CircleAvatar(backgroundColor: player.color, child: Text(player.name[0], style: const TextStyle(color: Color(0xff101400), fontWeight: FontWeight.w800))), const SizedBox(width: 12), Expanded(child: Text(player.name, style: const TextStyle(fontWeight: FontWeight.w700))), Text('${player.today}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
      ]));

  Widget _history() {
    final days = List.generate(7, (index) => DateTime.now().subtract(Duration(days: 6 - index)));
    final max = days.map((day) => _daily[_key(day)] ?? 0).fold(1, (a, b) => a > b ? a : b);
    return _shell('Histórico', ListView(children: [
      _stat('Total acumulado', '$_total flexões'), _stat('Sequência atual', '$_streak ${_streak == 1 ? 'dia' : 'dias'}'), _stat('Média necessária', '${((_goal - _total) / _daysLeft).ceil()} por dia'), _stat('Maior dia', '${_daily.values.fold(0, (a, b) => a > b ? a : b)} flexões'),
      const SizedBox(height: 18), const Text('Totais por período', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 12),
      SegmentedButton<_Period>(
        segments: const [
          ButtonSegment(value: _Period.semana, label: Text('Semana')),
          ButtonSegment(value: _Period.mes, label: Text('Mês')),
          ButtonSegment(value: _Period.ano, label: Text('Ano')),
        ],
        selected: {_historyPeriod},
        onSelectionChanged: (selection) => setState(() => _historyPeriod = selection.first),
      ),
      const SizedBox(height: 12), _stat('Total no período', '${_periodTotal(_historyPeriod)} flexões'),
      const SizedBox(height: 18), const Text('Últimos 7 dias', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 6),
      const Text('Toque em um dia para editar ou remover o registro.', style: TextStyle(color: Color(0xff657064), fontSize: 12)), const SizedBox(height: 12),
      Container(height: 180, padding: const EdgeInsets.all(16), decoration: _card(), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: days.map((day) { final amount = _daily[_key(day)] ?? 0; final height = amount == 0 ? 5.0 : 112.0 * amount / max; return Expanded(child: GestureDetector(onTap: () => _editDay(day), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [Text('$amount', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), const SizedBox(height: 6), Container(height: height, margin: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: day.day == DateTime.now().day ? const Color(0xff5d8f16) : const Color(0xffb8d68b), borderRadius: BorderRadius.circular(6))), const SizedBox(height: 8), Text('${day.day}/${day.month}', style: const TextStyle(fontSize: 10, color: Color(0xff657064))) ]))); }).toList())),
      const SizedBox(height: 14),
      OutlinedButton.icon(onPressed: _pickDay, icon: const Icon(Icons.edit_calendar_outlined), label: const Text('Editar outro dia'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
    ]));
  }

  Widget _stat(String label, String value) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(18), decoration: _card(), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w800))]));

  Widget _group() => _shell('Seu grupo', ListView(children: [
      Container(padding: const EdgeInsets.all(22), decoration: _card(radius: 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('FLEXÃO 3000', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), const SizedBox(height: 8),
        const Text('Código para convidar amigos', style: TextStyle(color: Color(0xff657064))), const SizedBox(height: 14),
        Row(children: [
          const Expanded(child: SelectableText(_inviteCode, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 2, color: Color(0xff5d8f16)))),
          IconButton(onPressed: _shareInvite, icon: const Icon(Icons.share_outlined), tooltip: 'Compartilhar código'),
        ]),
      ])),
      const SizedBox(height: 16), OutlinedButton.icon(onPressed: _showGroupSheet, icon: const Icon(Icons.person_add_alt_1), label: const Text('Convidar ou entrar em grupo'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50))),
      const SizedBox(height: 24), const Text('Participantes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 10), ..._players.map((player) => _member(player)),
    ]));

  Widget _member(Player player) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14), decoration: _card(radius: 16), child: Row(children: [CircleAvatar(backgroundColor: player.color, child: Text(player.name[0], style: const TextStyle(color: Color(0xff101400), fontWeight: FontWeight.w800))), const SizedBox(width: 12), Text(player.name, style: const TextStyle(fontWeight: FontWeight.w700))]));

  void _showGroupSheet() {
    final code = TextEditingController();
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))), builder: (sheetContext) => Padding(padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(sheetContext).viewInsets.bottom), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Convidar amigos', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)), const SizedBox(height: 8), const Text('Envie este código para eles entrarem no seu desafio.', style: TextStyle(color: Color(0xff657064))), const SizedBox(height: 18),
      Container(width: double.infinity, padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: const Color(0xffedf4e5), borderRadius: BorderRadius.circular(16)), child: const Center(child: SelectableText(_inviteCode, style: TextStyle(color: Color(0xff416b0a), fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2)))), const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _shareInvite, icon: const Icon(Icons.share_outlined), label: const Text('Compartilhar código'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))), const SizedBox(height: 24),
      const Text('Já recebeu um código?'), const SizedBox(height: 8), TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: _input('Ex.: FLEX-2026')), const SizedBox(height: 12), FilledButton(onPressed: () => Navigator.pop(sheetContext), style: _fullButton(), child: const Text('Entrar no grupo')),
    ])));
  }

  BoxDecoration _card({double radius = 20, bool shadow = false}) => BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xffe1e6de)), borderRadius: BorderRadius.circular(radius), boxShadow: shadow ? const [BoxShadow(color: Color(0x12000000), blurRadius: 20, offset: Offset(0, 8))] : null);
  Widget _pill(String label) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: const Color(0xffe6f2d4), borderRadius: BorderRadius.circular(99)), child: Text(label, style: const TextStyle(color: Color(0xff416b0a), fontWeight: FontWeight.w700)));
  String _key(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
