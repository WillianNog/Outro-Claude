import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

SupabaseClient get _db => Supabase.instance.client;

const _qrJoinPrefix = 'metafit://join/';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isEmpty ||
      supabasePublishableKey.isEmpty ||
      !supabaseUrl.startsWith('http')) {
    runApp(const _ConfigMissingApp());
    return;
  }
  await Supabase.initialize(
      url: supabaseUrl, publishableKey: supabasePublishableKey);
  runApp(const MetaFitApp());
}

class _ConfigMissingApp extends StatelessWidget {
  const _ConfigMissingApp();
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Configuração do Supabase ausente ou inválida.\n\n'
                'Copie lib/supabase_config.dart.sample para lib/supabase_config.dart '
                'e preencha supabaseUrl/supabasePublishableKey.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      );
}

// ─── App ──────────────────────────────────────────────────────────────────────

class MetaFitApp extends StatelessWidget {
  const MetaFitApp({super.key});

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
          scaffoldBackgroundColor: const Color(0xfff5f7fa),
          textTheme: GoogleFonts.interTextTheme(),
          colorScheme: const ColorScheme.light(
            primary: Color(0xff2A6DF4),
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        home: _db.auth.currentSession != null
            ? const _AuthedRouter()
            : const WelcomeScreen(),
      );
}

// Decide para onde mandar o usuário logado (configurar grupo ou ir direto ao app)
class _AuthedRouter extends StatefulWidget {
  const _AuthedRouter();
  @override
  State<_AuthedRouter> createState() => _AuthedRouterState();
}

class _AuthedRouterState extends State<_AuthedRouter> {
  bool _loading = true;
  String? _groupId;
  String _displayName = 'Você';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        );
      }
      return;
    }
    try {
      final profile = await _db
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _groupId = profile?['active_group_id'] as String?;
          _displayName = profile?['display_name'] as String? ?? 'Você';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_groupId == null) {
      return GroupSetupScreen(displayName: _displayName);
    }
    return HomeScreen(
      userName: _displayName,
      groupId: _groupId!,
      localMode: false,
    );
  }
}

// ─── Tela de boas-vindas / login ──────────────────────────────────────────────

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _auth() async {
    final name = _name.text.trim().isEmpty ? 'Você' : _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Preencha e-mail e senha para continuar.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'A senha precisa ter pelo menos 6 caracteres.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      AuthResponse res;
      try {
        res = await _db.auth
            .signInWithPassword(email: email, password: password);
      } on AuthException {
        res = await _db.auth.signUp(email: email, password: password);
      }

      if (res.session == null) {
        setState(() {
          _error =
              'Cadastro realizado! Verifique seu e-mail para confirmar a conta.';
          _loading = false;
        });
        return;
      }

      await _db.from('profiles').upsert(
        {'id': res.user!.id, 'display_name': name},
        onConflict: 'id',
        ignoreDuplicates: true,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const _AuthedRouter()),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao conectar. Verifique sua internet.';
        _loading = false;
      });
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Preencha o e-mail acima e toque em "Esqueci minha senha" de novo.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _db.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      setState(() {
        _error = 'Enviamos um link de redefinição para $email. Confira também o spam.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Não deu para enviar agora. Verifique sua internet e tente de novo.';
        _loading = false;
      });
    }
  }

  void _localMode() {
    final name = _name.text.trim().isEmpty ? 'Você' : _name.text.trim();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            HomeScreen(userName: name, groupId: '', localMode: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 40),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xff2A6DF4),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.fitness_center_rounded,
                    color: Colors.white, size: 34),
              ),
              const SizedBox(height: 28),
              const Text('Sua meta,\nseu grupo.',
                  style: TextStyle(
                      fontSize: 38, fontWeight: FontWeight.w800, height: 1.05)),
              const SizedBox(height: 14),
              const Text(
                'Registre suas flexões e acompanhe a evolução de todos até o fim do ano.',
                style: TextStyle(
                    color: Color(0xff67707d), fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 34),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDeco('Seu apelido'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDeco('E-mail'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                decoration: _inputDeco('Senha (mín. 6 caracteres)').copyWith(
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(_showPassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : _forgotPassword,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                  child: const Text('Esqueci minha senha', style: TextStyle(fontSize: 12.5)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(
                        color: _error!.contains('Verifique seu e-mail') ||
                                _error!.contains('Enviamos um link')
                            ? Colors.orange[700]
                            : Colors.red)),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _loading ? null : _auth,
                style: _btnFull(),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Entrar / Cadastrar'),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _localMode,
                  child: const Text('Usar sem conta (só neste celular)'),
                ),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'MetaFit · desafio entre amigos',
                  style: TextStyle(color: Color(0xff67707d), fontSize: 12),
                ),
              ),
            ]),
          ),
        ),
      );
}

// ─── Escanear QR do grupo ──────────────────────────────────────────────────────

class _ScanQrScreen extends StatefulWidget {
  const _ScanQrScreen();
  @override
  State<_ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<_ScanQrScreen> {
  bool _handled = false;

  String? _extractCode(String raw) {
    if (raw.startsWith(_qrJoinPrefix)) {
      final code = raw.substring(_qrJoinPrefix.length).trim();
      return code.isEmpty ? null : code.toUpperCase();
    }
    if (raw.trim().toUpperCase().startsWith('META-')) {
      return raw.trim().toUpperCase();
    }
    return null;
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (raw == null) return;
    final code = _extractCode(raw);
    if (code == null) return;
    _handled = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Escanear código do grupo'),
        ),
        body: Stack(fit: StackFit.expand, children: [
          MobileScanner(onDetect: _onDetect),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2.5),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 44,
            left: 24,
            right: 24,
            child: Text(
              'Aponte a câmera para o QR do seu amigo',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ]),
      );
}

// ─── Configurar grupo (criar ou entrar) ───────────────────────────────────────

class GroupSetupScreen extends StatefulWidget {
  const GroupSetupScreen({super.key, required this.displayName});
  final String displayName;
  @override
  State<GroupSetupScreen> createState() => _GroupSetupScreenState();
}

class _GroupSetupScreenState extends State<GroupSetupScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return 'META-${List.generate(4, (_) => chars[rng.nextInt(chars.length)]).join()}';
  }

  Future<void> _createGroup() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _db.auth.currentUser!.id;
      Map<String, dynamic>? group;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          group = await _db.from('groups').insert({
            'name': 'MetaFit',
            'invite_code': _randomCode(),
            'owner_id': uid,
          }).select().single();
          break;
        } on PostgrestException catch (e) {
          if (e.code == '23505' && attempt < 2) continue;
          rethrow;
        }
      }
      final gid = group!['id'] as String;
      await _db
          .from('group_members')
          .insert({'group_id': gid, 'user_id': uid});
      await _db
          .from('profiles')
          .update({'active_group_id': gid}).eq('id', uid);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => HomeScreen(
            userName: widget.displayName, groupId: gid, localMode: false),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao criar grupo. Tente novamente.';
        _loading = false;
      });
    }
  }

  Future<void> _scanQr() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ScanQrScreen()),
    );
    if (code == null || !mounted) return;
    _codeCtrl.text = code;
    _joinGroup();
  }

  Future<void> _joinGroup() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Digite o código do grupo.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _db.rpc('join_group_by_code', params: {'p_code': code});
      final list = rows as List;
      if (list.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'Código não encontrado. Verifique e tente novamente.';
          _loading = false;
        });
        return;
      }
      final gid = (list.first as Map)['group_id'] as String;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => HomeScreen(
            userName: widget.displayName, groupId: gid, localMode: false),
      ));
    } on PostgrestException catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro do servidor. Tente novamente em instantes.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Sem conexão. Verifique sua internet e tente de novo.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 40),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    color: const Color(0xff2A6DF4),
                    borderRadius: BorderRadius.circular(24)),
                child: const Icon(Icons.group_rounded,
                    color: Colors.white, size: 34),
              ),
              const SizedBox(height: 28),
              Text('Olá, ${widget.displayName}!',
                  style: const TextStyle(
                      fontSize: 32, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Text(
                'Crie um grupo para convidar amigos, ou entre em um grupo com o código que recebeu.',
                style: TextStyle(
                    color: Color(0xff67707d), fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 36),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: _cardDeco(radius: 20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Criar novo grupo',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 6),
                      const Text(
                          'Você vira o admin e recebe um código para compartilhar.',
                          style: TextStyle(color: Color(0xff67707d))),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loading ? null : _createGroup,
                        style: _btnFull(),
                        child: const Text('Criar grupo'),
                      ),
                    ]),
              ),
              const SizedBox(height: 24),
              const Row(children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text('ou', style: TextStyle(color: Color(0xff67707d))),
                ),
                Expanded(child: Divider()),
              ]),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: _cardDeco(radius: 20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Entrar com código',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 6),
                      const Text('Cole o código que alguém compartilhou.',
                          style: TextStyle(color: Color(0xff67707d))),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _codeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: _inputDeco('Ex.: META-A1B2'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _loading ? null : _joinGroup,
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50)),
                        child: const Text('Entrar no grupo'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _loading ? null : _scanQr,
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        label: const Text('ou escanear QR do grupo'),
                      ),
                    ]),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style: const TextStyle(color: Colors.red, fontSize: 14)),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ]),
          ),
        ),
      );
}

// ─── Tela principal ───────────────────────────────────────────────────────────

enum _Period { semana, mes, ano }

class _Player {
  const _Player(this.name, this.today, this.color);
  final String name;
  final int today;
  final Color color;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.userName,
    required this.groupId,
    required this.localMode,
  });
  final String userName;
  final String groupId;
  final bool localMode;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _goal = 3000;
  static const _storageKey = 'dailyPushupsV2';
  Map<String, int> _daily = {};
  int _tab = 0;
  bool _loading = true;
  _Period _histPeriod = _Period.semana;

  List<_Player> _players = [];
  String _inviteCode = '';
  String _groupName = 'MetaFit';
  String? _groupOwnerId;
  RealtimeChannel? _rtChannel;
  Timer? _rankingDebounce;
  bool _syncError = false;
  final Set<String> _pendingSync = {};

  String get _todayKey => _fmt(DateTime.now());
  int get _today => _daily[_todayKey] ?? 0;
  int get _total => _daily.values.fold(0, (a, b) => a + b);
  int get _daysLeft {
    final now = DateTime.now();
    return DateTime(now.year, 12, 31)
            .difference(DateTime(now.year, now.month, now.day))
            .inDays +
        1;
  }

  int get _streak {
    var d = DateTime.now();
    if ((_daily[_fmt(d)] ?? 0) == 0) d = d.subtract(const Duration(days: 1));
    var s = 0;
    while ((_daily[_fmt(d)] ?? 0) > 0) {
      s++;
      d = d.subtract(const Duration(days: 1));
    }
    return s;
  }

  String get _medal => _streak >= 100
      ? '🏆'
      : _streak >= 30
          ? '🥇'
          : _streak >= 7
              ? '🥈'
              : _streak >= 3
                  ? '🥉'
                  : '⚡';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rtChannel?.unsubscribe();
    _rankingDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.localMode) {
      await _loadLocal();
    } else {
      await Future.wait([_loadEntries(), _loadGroup()]);
      _subscribeRealtime();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        final m = Map<String, dynamic>.from(decoded as Map);
        _daily =
            m.map((k, v) => MapEntry(k, v is int ? v : int.tryParse('$v') ?? 0));
      } catch (e) {
        debugPrint('MetaFit: dados locais corrompidos, reiniciando ($e)');
        _daily = {_todayKey: 25};
      }
    } else {
      _daily[_todayKey] = 25;
    }
    _players = [
      _Player(widget.userName, _today, const Color(0xffffc857)),
      const _Player('Seu amigo', 29, Color(0xffff8b7b)),
    ];
    _inviteCode = 'META-2026';
  }

  void _syncLocalPlayer() {
    if (!widget.localMode || _players.isEmpty) return;
    _players[0] = _Player(widget.userName, _today, _players[0].color);
  }

  Future<void> _loadEntries() async {
    try {
      final rows = await _db
          .from('entries')
          .select('date, count')
          .eq('user_id', _db.auth.currentUser!.id);
      final m = <String, int>{};
      for (final r in rows as List) {
        m[r['date'] as String] = r['count'] as int;
      }
      if (mounted) {
        setState(() {
          _daily = m;
          _syncError = false;
        });
      }
    } catch (e) {
      debugPrint('MetaFit: falha ao carregar entradas ($e)');
      if (mounted) setState(() => _syncError = true);
    }
  }

  Future<void> _loadGroup() async {
    try {
      final g = await _db
          .from('groups')
          .select('id, name, invite_code, owner_id')
          .eq('id', widget.groupId)
          .single();
      _inviteCode = g['invite_code'] as String;
      _groupName = g['name'] as String;
      _groupOwnerId = g['owner_id'] as String?;
      if (mounted) setState(() => _syncError = false);
      await _loadRanking();
    } catch (e) {
      debugPrint('MetaFit: falha ao carregar grupo ($e)');
      if (mounted) setState(() => _syncError = true);
    }
  }

  Future<void> _loadRanking() async {
    try {
      final today = _fmt(DateTime.now());
      final members = await _db
          .from('group_members')
          .select('user_id, profiles(display_name)')
          .eq('group_id', widget.groupId);

      const colors = [
        Color(0xffffc857),
        Color(0xffff8b7b),
        Color(0xffb79cff),
        Color(0xffffb7c5),
        Color(0xffffd7a8),
      ];

      final memberList = members as List;
      final memberIds = memberList.map((m) => m['user_id'] as String).toList();
      final counts = <String, int>{};
      if (memberIds.isNotEmpty) {
        final rows = await _db
            .from('entries')
            .select('user_id, count')
            .eq('date', today)
            .inFilter('user_id', memberIds);
        for (final r in rows as List) {
          counts[r['user_id'] as String] = r['count'] as int;
        }
      }

      final List<_Player> players = [];
      int ci = 0;
      for (final m in memberList) {
        final uid = m['user_id'] as String;
        final name =
            (m['profiles'] as Map?)!['display_name'] as String? ?? 'Amigo';
        players.add(
            _Player(name, counts[uid] ?? 0, colors[ci % colors.length]));
        ci++;
      }
      players.sort((a, b) => b.today.compareTo(a.today));
      if (mounted) {
        setState(() {
          _players = players;
          _syncError = false;
        });
      }
    } catch (e) {
      debugPrint('MetaFit: falha ao carregar ranking ($e)');
      if (mounted) setState(() => _syncError = true);
    }
  }

  void _subscribeRealtime() {
    if (widget.groupId.isEmpty) return;
    _rtChannel = _db
        .channel('entries_${widget.groupId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'entries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: widget.groupId,
          ),
          callback: (_) {
            _rankingDebounce?.cancel();
            _rankingDebounce =
                Timer(const Duration(milliseconds: 400), _loadRanking);
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            debugPrint('MetaFit: erro no canal realtime ($error)');
          }
        });
  }

  void _add(int n) {
    setState(() {
      _daily[_todayKey] = _today + n;
      _syncLocalPlayer();
    });
    widget.localMode ? _saveLocal() : _saveCloud();
  }

  void _undo() {
    if (_today == 0) return;
    setState(() {
      _daily[_todayKey] = _today - 1;
      _syncLocalPlayer();
    });
    widget.localMode ? _saveLocal() : _saveCloud();
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_daily));
  }

  Future<void> _saveCloud() async {
    try {
      await _db.from('entries').upsert({
        'user_id': _db.auth.currentUser!.id,
        'date': _todayKey,
        'count': _today,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,date');
      if (mounted && _pendingSync.remove(_todayKey)) setState(() {});
    } catch (e) {
      debugPrint('MetaFit: falha ao salvar na nuvem ($e)');
      if (mounted) setState(() => _pendingSync.add(_todayKey));
    }
  }

  DateTime _parseKey(String k) {
    final p = k.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  int _periodTotal(_Period period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = switch (period) {
      _Period.semana => today.subtract(const Duration(days: 6)),
      _Period.mes => DateTime(today.year, today.month, 1),
      _Period.ano => DateTime(today.year, 1, 1),
    };
    return _daily.entries
        .where((e) => !_parseKey(e.key).isBefore(from))
        .fold(0, (s, e) => s + e.value);
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: DateTime(now.year, 1, 1),
        lastDate: now);
    if (picked != null) _editDay(picked);
  }

  Future<void> _editDay(DateTime day) async {
    final ctrl = TextEditingController(text: '${_daily[_fmt(day)] ?? 0}');
    int? result;
    try {
      result = await showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Editar ${day.day}/${day.month}/${day.year}'),
          content: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: _inputDeco('Quantidade de flexões')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 0),
                child: const Text('Remover')),
            FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, int.tryParse(ctrl.text) ?? 0),
                child: const Text('Salvar')),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
    if (result == null || !mounted) return;
    final key = _fmt(day);
    final value = result;
    setState(() {
      if (value <= 0) {
        _daily.remove(key);
      } else {
        _daily[key] = value;
      }
      _syncLocalPlayer();
    });
    if (widget.localMode) {
      _saveLocal();
    } else {
      try {
        final uid = _db.auth.currentUser!.id;
        if (value <= 0) {
          await _db.from('entries').delete().eq('user_id', uid).eq('date', key);
        } else {
          await _db.from('entries').upsert({
            'user_id': uid,
            'date': key,
            'count': value,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id,date');
        }
        if (mounted && _pendingSync.remove(key)) setState(() {});
      } catch (e) {
        debugPrint('MetaFit: falha ao salvar edição de dia ($e)');
        if (mounted) setState(() => _pendingSync.add(key));
      }
    }
  }

  void _shareInvite() {
    SharePlus.instance.share(ShareParams(
        text:
            'Bora somar flexões comigo! Entre no grupo MetaFit com o código $_inviteCode.'));
  }

  Future<void> _signOut() async {
    try {
      await _db.auth.signOut();
    } catch (e) {
      debugPrint('MetaFit: falha ao sair da conta ($e)');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não deu para sair agora. Tente de novo.')));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()));
  }

  Future<void> _deleteAccount() async {
    final ownsGroup = !widget.localMode &&
        _groupOwnerId != null &&
        _groupOwnerId == _db.auth.currentUser?.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir sua conta?'),
        content: Text(
          'Isso apaga sua conta, seu histórico de flexões e seu perfil, sem volta.'
          '${ownsGroup ? ' Se você for dono de algum grupo, o grupo some pra todo mundo também.' : ''}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await _db.functions.invoke('delete-account');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não deu para excluir agora. Tente de novo em instantes.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
          child: [_dashboard(), _ranking(), _history(), _group()][_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Início'),
          NavigationDestination(
              icon: Icon(Icons.emoji_events_outlined),
              selectedIcon: Icon(Icons.emoji_events),
              label: 'Ranking'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Histórico'),
          NavigationDestination(
              icon: Icon(Icons.group_outlined),
              selectedIcon: Icon(Icons.group),
              label: 'Grupo'),
        ],
      ),
    );
  }

  // ── Shells e helpers de layout ──────────────────────────────────────────────

  Widget _shell(String title, Widget child, {String? badge}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w800))),
            if (badge != null) _pill(badge),
          ]),
          const SizedBox(height: 20),
          Expanded(child: child),
        ]),
      );

  // ── Dashboard ───────────────────────────────────────────────────────────────

  Widget _dashboard() => _shell(
        'Olá, ${widget.userName}',
        ListView(children: [
          if (_syncError)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(children: [
                Icon(Icons.wifi_off_rounded, color: Colors.orange[800], size: 20),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text('Não deu para atualizar os dados agora.',
                        style: TextStyle(fontSize: 13))),
                TextButton(
                  onPressed: () {
                    setState(() => _syncError = false);
                    _load();
                  },
                  child: const Text('Tentar de novo'),
                ),
              ]),
            ),
          Text('DESAFIO 2026',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4)),
          const SizedBox(height: 10),
          _goalCard(),
          const SizedBox(height: 16),
          _streakCard(),
          const Text('Adicionar flexões',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 12),
          Row(
            children: [1, 5, 10]
                .map((n) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: n == 10 ? 0 : 10),
                        child: FilledButton(
                          onPressed: () => _add(n),
                          style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 17),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          child: Text('+$n',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: _today == 0 ? null : _undo,
              icon: const Icon(Icons.undo),
              label: const Text('Desfazer 1 flexão'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48))),
          const SizedBox(height: 20),
          _todayCard(),
          if (!widget.localMode) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Sair da conta'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: _deleteAccount,
                style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
                child: const Text('Excluir minha conta', style: TextStyle(fontSize: 12.5)),
              ),
            ),
          ],
        ]),
        badge: '🔥 $_today hoje',
      );

  Widget _goalCard() {
    final progress = (_total / _goal).clamp(0.0, 1.0);
    return Container(
        padding: const EdgeInsets.all(22),
        decoration: _cardDeco(radius: 28, shadow: true),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$_total',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  height: 1)),
          const SizedBox(height: 4),
          const Text('de 3.000 flexões',
              style: TextStyle(color: Color(0xff67707d), fontSize: 16)),
          const SizedBox(height: 20),
          ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 12,
                  backgroundColor: const Color(0xffe7ecf3))),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${_goal - _total} faltam',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('$_daysLeft dias até 31 dez',
                style: const TextStyle(color: Color(0xff67707d))),
          ]),
        ]));
  }

  Widget _streakCard() {
    if (_streak == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: _cardDeco(radius: 18),
      child: Row(children: [
        Text(_medal, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(
            child: Text(
                '$_streak ${_streak == 1 ? 'dia seguido' : 'dias seguidos'}',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16))),
      ]),
    );
  }

  Widget _todayCard() {
    final pending = !widget.localMode && _pendingSync.contains(_todayKey);
    return Container(
        padding: const EdgeInsets.all(18),
        decoration: _cardDeco(),
        child: Row(children: [
          Icon(
              pending
                  ? Icons.cloud_off_outlined
                  : Icons.calendar_today_outlined,
              color: pending ? Colors.orange[700] : const Color(0xff2A6DF4)),
          const SizedBox(width: 12),
          Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Hoje', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
                pending
                    ? 'Não sincronizado ainda. Toque para tentar de novo.'
                    : widget.localMode
                        ? 'Salvo neste celular.'
                        : 'Salvo na nuvem, sincronizado com o grupo.',
                style: TextStyle(
                    color:
                        pending ? Colors.orange[700] : const Color(0xff67707d),
                    fontSize: 12)),
          ])),
          if (pending)
            IconButton(
                onPressed: _saveCloud,
                icon: const Icon(Icons.refresh, color: Color(0xff2A6DF4)),
                tooltip: 'Tentar sincronizar de novo'),
          Text('$_today',
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        ]));
  }

  // ── Ranking ─────────────────────────────────────────────────────────────────

  Widget _ranking() {
    final count = _players.length;
    return _shell(
      'Ranking',
      ListView(children: [
        const Text('HOJE',
            style: TextStyle(
                color: Color(0xff2A6DF4),
                letterSpacing: 1.5,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        if (_players.isEmpty)
          const Text(
              'Nenhum participante ainda. Convide amigos pelo código do grupo.',
              style: TextStyle(color: Color(0xff67707d)))
        else
          ..._players.asMap().entries.map((e) => _rankItem(e.key + 1, e.value)),
        if (widget.localMode) ...[
          const SizedBox(height: 18),
          const Text(
              'Para ver amigos no ranking, crie uma conta e um grupo real.',
              style: TextStyle(color: Color(0xff67707d))),
        ],
      ]),
      badge: '$count ${count == 1 ? 'pessoa' : 'pessoas'}',
    );
  }

  Widget _rankItem(int rank, _Player p) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Row(children: [
        Text('$rank.',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(width: 14),
        CircleAvatar(
            backgroundColor: p.color,
            child: Text(p.name[0].toUpperCase(),
                style: const TextStyle(
                    color: Color(0xff141a24), fontWeight: FontWeight.w800))),
        const SizedBox(width: 12),
        Expanded(
            child: Text(p.name,
                style: const TextStyle(fontWeight: FontWeight.w700))),
        Text('${p.today}',
            style:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
      ]));

  // ── Histórico ───────────────────────────────────────────────────────────────

  Widget _history() {
    final days = List.generate(
        7, (i) => DateTime.now().subtract(Duration(days: 6 - i)));
    final max = days
        .map((d) => _daily[_fmt(d)] ?? 0)
        .fold(1, (a, b) => a > b ? a : b);
    return _shell(
      'Histórico',
      ListView(children: [
        _stat('Total acumulado', '$_total flexões'),
        _stat('Sequência atual', '$_streak ${_streak == 1 ? 'dia' : 'dias'}'),
        _stat('Média necessária',
            '${((_goal - _total) / _daysLeft).ceil()} por dia'),
        _stat('Maior dia',
            '${_daily.values.fold(0, (a, b) => a > b ? a : b)} flexões'),
        const SizedBox(height: 18),
        const Text('Totais por período',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        SegmentedButton<_Period>(
          segments: const [
            ButtonSegment(value: _Period.semana, label: Text('Semana')),
            ButtonSegment(value: _Period.mes, label: Text('Mês')),
            ButtonSegment(value: _Period.ano, label: Text('Ano')),
          ],
          selected: {_histPeriod},
          onSelectionChanged: (s) =>
              setState(() => _histPeriod = s.first),
        ),
        const SizedBox(height: 12),
        _stat('Total no período', '${_periodTotal(_histPeriod)} flexões'),
        const SizedBox(height: 18),
        const Text('Últimos 7 dias',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Toque em um dia para editar o registro.',
            style: TextStyle(color: Color(0xff67707d), fontSize: 12)),
        const SizedBox(height: 12),
        Container(
          height: 180,
          padding: const EdgeInsets.all(16),
          decoration: _cardDeco(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: days.map((day) {
              final amount = _daily[_fmt(day)] ?? 0;
              final h = amount == 0 ? 5.0 : 112.0 * amount / max;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _editDay(day),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('$amount',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12)),
                        const SizedBox(height: 6),
                        Container(
                          height: h,
                          margin:
                              const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: day.day == DateTime.now().day
                                ? const Color(0xff2A6DF4)
                                : const Color(0xffaec8f5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('${day.day}/${day.month}',
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xff67707d))),
                      ]),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
            onPressed: _pickDay,
            icon: const Icon(Icons.edit_calendar_outlined),
            label: const Text('Editar outro dia'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48))),
      ]),
    );
  }

  Widget _stat(String label, String value) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco(),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ]));

  // ── Grupo ───────────────────────────────────────────────────────────────────

  Widget _group() => _shell(
        'Seu grupo',
        ListView(children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: _cardDeco(radius: 24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_groupName,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Código para convidar amigos',
                  style: TextStyle(color: Color(0xff67707d))),
              const SizedBox(height: 14),
              if (widget.localMode)
                const Text(
                    'Entre com uma conta para criar um grupo real e convidar amigos.',
                    style: TextStyle(color: Color(0xff67707d)))
              else ...[
                Row(children: [
                  Expanded(
                    child: SelectableText(_inviteCode,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: Color(0xff2A6DF4))),
                  ),
                  IconButton(
                      onPressed: _shareInvite,
                      icon: const Icon(Icons.share_outlined),
                      tooltip: 'Compartilhar código'),
                ]),
                const SizedBox(height: 18),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xffe2e7ef)),
                    ),
                    child: QrImageView(
                      data: '$_qrJoinPrefix$_inviteCode',
                      size: 160,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text('Peça para seu amigo escanear pelo app',
                      style: TextStyle(color: Color(0xff67707d), fontSize: 12)),
                ),
              ],
            ]),
          ),
          if (!widget.localMode) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
                onPressed: _shareInvite,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Convidar amigos'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50))),
          ],
          const SizedBox(height: 24),
          const Text('Participantes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ..._players.map((p) => _memberTile(p)),
        ]),
      );

  Widget _memberTile(_Player p) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(radius: 16),
      child: Row(children: [
        CircleAvatar(
            backgroundColor: p.color,
            child: Text(p.name[0].toUpperCase(),
                style: const TextStyle(
                    color: Color(0xff141a24), fontWeight: FontWeight.w800))),
        const SizedBox(width: 12),
        Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]));

  // ── Helpers visuais ─────────────────────────────────────────────────────────

  Widget _pill(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: const Color(0xffe1ebff),
          borderRadius: BorderRadius.circular(99)),
      child: Text(label,
          style: const TextStyle(
              color: Color(0xff1039a0), fontWeight: FontWeight.w700)));

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

InputDecoration _inputDeco(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none));

ButtonStyle _btnFull() => FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(56),
    shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)));

BoxDecoration _cardDeco({double radius = 20, bool shadow = false}) =>
    BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffe2e7ef)),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow
            ? const [
                BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 20,
                    offset: Offset(0, 8))
              ]
            : null);
