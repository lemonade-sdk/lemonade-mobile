import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_nexus_sdk/lemonade_nexus_sdk.dart'
    show MeshPortStatus, SessionMoveEvent;

import '../models/server_config.dart';
import '../services/mesh_service.dart';
import '../utils/server_identity.dart';

enum MeshPhase {
  /// No mesh account on this device yet: Mesh mode offers Create / Join.
  notSetUp,

  /// Set up, but not running (another mode is active, or the app is in the
  /// background).
  idle,
  connecting,
  connected,

  /// The last connect failed; [MeshState.error] says why.
  error,
}

class MeshState {
  final MeshPhase phase;
  final MeshAccount? account;
  final MeshSession? session;

  /// Selection and the inference devices the mesh port can reach.
  final MeshPortStatus port;
  final String? error;

  const MeshState({
    this.phase = MeshPhase.notSetUp,
    this.account,
    this.session,
    this.port = MeshPortStatus.stopped,
    this.error,
  });

  bool get isSetUp => account != null;

  /// "auto", or the node ID that serves every request.
  String get selection => account?.selection ?? 'auto';

  /// Display name of the current selection.
  String get selectionLabel {
    if (selection == 'auto') return 'Auto';
    for (final d in port.devices) {
      if (d.nodeId == selection) return d.label;
    }
    return 'Selected device';
  }

  int get onlineDevices => port.devices.where((d) => d.isOnline).length;

  MeshState copyWith({
    MeshPhase? phase,
    MeshAccount? account,
    MeshSession? session,
    MeshPortStatus? port,
    String? error,
    bool clearError = false,
  }) =>
      MeshState(
        phase: phase ?? this.phase,
        account: account ?? this.account,
        session: session ?? this.session,
        port: port ?? this.port,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Mesh mode: the Lemonade Nexus device account and the running mesh.
///
/// [activate] / [deactivate] are driven by the app mode (appModeProvider);
/// this notifier does not watch the mode itself, because the mode in turn
/// follows [meshServerProvider]. While active it also follows the app
/// lifecycle: the mesh port stops when the app leaves the foreground, so
/// another app cannot use the loopback port meanwhile, and reconnects on
/// resume.
class MeshNotifier extends StateNotifier<MeshState> with WidgetsBindingObserver {
  MeshNotifier() : super(const MeshState(phase: MeshPhase.idle)) {
    WidgetsBinding.instance.addObserver(this);
    _hydrated = _hydrate();
  }

  late final Future<void> _hydrated;
  MeshService? _service;
  bool _active = false;
  Timer? _poll;
  StreamSubscription<SessionMoveEvent>? _moves;
  DateTime? _lastRejoin;

  /// One connect at a time; later callers wait for it.
  Future<void>? _connecting;

  Future<void> _hydrate() async {
    final account = await MeshAccount.load();
    if (!mounted) return;
    state = account == null
        ? const MeshState(phase: MeshPhase.notSetUp)
        : MeshState(phase: MeshPhase.idle, account: account);
  }

  Future<MeshService> _ensureService() async {
    final existing = _service;
    if (existing != null) return existing;
    final service = await MeshService.start();
    _moves = service.sessionMoves.listen(_onSessionMoved);
    return _service = service;
  }

  /// The network server that issued the session left. A silent move needs
  /// nothing but the newer network epoch; otherwise the session is gone and
  /// the device joins again (at most every 30 seconds).
  Future<void> _onSessionMoved(SessionMoveEvent move) async {
    debugPrint('Mesh session moved: ${move.fromHost} -> ${move.toHost} '
        'silent=${move.silent} ${move.error}');
    if (!_active || state.phase != MeshPhase.connected) return;
    if (move.silent) {
      final account = state.account;
      if (account != null && move.epoch > account.tier1Epoch) {
        final saved = account.copyWith(tier1Epoch: move.epoch);
        await saved.save();
        if (mounted) state = state.copyWith(account: saved);
      }
      await refresh();
      return;
    }
    final last = _lastRejoin;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastRejoin = DateTime.now();
    await _connect();
  }

  /// Mesh mode turned on: connect when this device has a mesh account.
  Future<void> activate() async {
    _active = true;
    await _hydrated;
    if (state.isSetUp) await _connect();
  }

  /// Mesh mode turned off: stop the mesh and the mesh port.
  Future<void> deactivate() async {
    _active = false;
    await _stop(MeshPhase.idle);
  }

  /// "Create mesh": a new device identity whose own group is the new mesh.
  Future<void> create(String deviceName) =>
      _setUp(MeshAccount.create(deviceName.trim()), inviteCode: null);

  /// "Join mesh": a new device identity that joins the group of [inviteCode].
  Future<void> join(String inviteCode, String deviceName) => _setUp(
      MeshAccount.create(deviceName.trim()),
      inviteCode: normalizeInviteCode(inviteCode));

  Future<void> _setUp(MeshAccount account, {required String? inviteCode}) async {
    _active = true;
    state = MeshState(phase: MeshPhase.connecting, account: account);
    try {
      final service = await _ensureService();
      final session = await service.connect(account, inviteCode: inviteCode);
      final saved = account.copyWith(
          deviceName: session.deviceName,
          genesisKey: session.genesisKey,
          tier1Epoch: session.tier1Epoch,
          nodeId: session.nodeId);
      await saved.save();
      await _connected(service, saved, session);
    } catch (e) {
      // Nothing is saved: the next attempt starts with a fresh identity.
      state = MeshState(
          phase: MeshPhase.notSetUp, error: MeshException.from(e).message);
      rethrow;
    }
  }

  Future<void> _connect() =>
      _connecting ??= _doConnect().whenComplete(() => _connecting = null);

  Future<void> _doConnect() async {
    final account = state.account;
    if (account == null) return;
    state = state.copyWith(phase: MeshPhase.connecting, clearError: true);
    try {
      final service = await _ensureService();
      final session = await service.connect(account);
      var saved = account;
      if (session.tier1Epoch > account.tier1Epoch ||
          account.genesisKey == null ||
          account.nodeId != session.nodeId ||
          (session.deviceName != null && session.deviceName != account.deviceName)) {
        saved = account.copyWith(
            deviceName: session.deviceName,
            genesisKey: session.genesisKey,
            tier1Epoch: session.tier1Epoch,
            nodeId: session.nodeId);
        await saved.save();
      }
      if (!_active) {
        await service.stop();
        state = state.copyWith(phase: MeshPhase.idle);
        return;
      }
      await _connected(service, saved, session);
    } catch (e) {
      debugPrint('Mesh connect failed: $e');
      state = state.copyWith(
          phase: MeshPhase.error, error: MeshException.from(e).message);
    }
  }

  Future<void> _connected(
      MeshService service, MeshAccount account, MeshSession session) async {
    var selected = account;
    try {
      await service.select(account.selection);
    } catch (_) {
      // A device that left the group: fall back to Auto.
      selected = account.copyWith(selection: 'auto');
      await selected.save();
      await service.select('auto');
    }
    state = MeshState(
        phase: MeshPhase.connected, account: selected, session: session);
    await refresh();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _heartbeat());
  }

  /// Re-reads the devices and the selection; reconnects when the mesh dropped.
  Future<void> refresh() async {
    final service = _service;
    if (service == null || state.phase != MeshPhase.connected) return;
    try {
      final port = await service.portStatus();
      if (mounted) state = state.copyWith(port: port);
    } catch (e) {
      debugPrint('Mesh status failed: $e');
    }
  }

  Future<void> _heartbeat() async {
    final service = _service;
    if (service == null || !_active || state.phase != MeshPhase.connected) return;
    if (await service.isUp()) {
      await refresh();
    } else {
      await _connect();
    }
  }

  Future<void> retry() => _connect();

  /// Serve every request from [target] ("auto" or a node ID). [peerKey] is
  /// the API key of that device's lemond, when it requires one.
  Future<void> select(String target, {String? peerKey}) async {
    final account = state.account;
    final service = _service;
    if (account == null || service == null) return;
    await service.select(target);
    final keys = Map<String, String>.from(account.peerKeys);
    if (peerKey != null) {
      if (peerKey.trim().isEmpty) {
        keys.remove(target);
      } else {
        keys[target] = peerKey.trim();
      }
    }
    final saved = account.copyWith(selection: target, peerKeys: keys);
    await saved.save();
    state = state.copyWith(account: saved);
    await refresh();
  }

  /// A single-use invite code for this mesh: (code, expiry).
  Future<(String, DateTime?)> createInvite() async {
    final service = _service;
    if (service == null || state.phase != MeshPhase.connected) {
      throw const MeshException('Connect to your mesh first.');
    }
    final result = await service.createInvite();
    final code = result['link_token'] as String? ?? '';
    final expires = result['expires_at'];
    DateTime? expiry;
    if (expires is num) {
      expiry = DateTime.fromMillisecondsSinceEpoch(expires.toInt() * 1000);
    } else if (expires is String) {
      expiry = DateTime.tryParse(expires);
    }
    return (code, expiry);
  }

  /// Removes this device from the mesh and forgets its identity.
  Future<void> leave() async {
    final service = _service;
    if (service != null && state.phase == MeshPhase.connected) {
      try {
        await service.leave();
      } catch (e) {
        debugPrint('Mesh leave failed: $e');
      }
    }
    await _stop(MeshPhase.notSetUp);
    await MeshAccount.delete();
    state = const MeshState(phase: MeshPhase.notSetUp);
  }

  Future<void> _stop(MeshPhase phase) async {
    _poll?.cancel();
    _poll = null;
    await _connecting;
    final service = _service;
    if (service != null) {
      try {
        await service.stop();
      } catch (_) {}
    }
    if (mounted) {
      state = state.copyWith(phase: state.isSetUp ? phase : MeshPhase.notSetUp);
    }
  }

  @override
  // Not named `state`: that would hide StateNotifier.state in this method.
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (!_active || !state.isSetUp) return;
    if (lifecycle == AppLifecycleState.paused) {
      _stop(MeshPhase.idle);
    } else if (lifecycle == AppLifecycleState.resumed &&
        state.phase != MeshPhase.connected) {
      _connect();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _moves?.cancel();
    _service?.close();
    super.dispose();
  }
}

/// Invite codes are 8 digits (shown in groups) or full `lnk_…` tokens.
String normalizeInviteCode(String input) {
  final trimmed = input.trim();
  final digits = trimmed.replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^\d{8}$').hasMatch(digits) ? digits : trimmed;
}

final meshProvider =
    StateNotifierProvider<MeshNotifier, MeshState>((ref) => MeshNotifier());

/// The loopback mesh port as a server, while the mesh runs. The API key is
/// the selected device's lemond key, sent per request (see
/// LemonadeApiClient), never to the SDK.
final meshServerProvider = Provider<ServerConfig?>((ref) {
  final mesh = ref.watch(meshProvider);
  if (mesh.phase != MeshPhase.connected) return null;
  final selection = mesh.selection;
  return ServerConfig(
    baseUrl: 'http://127.0.0.1:$kMeshPortNumber',
    name: kMeshServerName,
    apiKey: selection == 'auto' ? null : mesh.account?.peerKeys[selection],
  );
});
