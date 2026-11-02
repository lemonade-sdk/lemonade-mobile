import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_nexus_sdk/lemonade_nexus_sdk.dart'
    show
        Invite,
        MeshEvent,
        MeshEventKind,
        MeshPortStatus,
        NetworkDevice,
        SessionMoveEvent,
        normalizeInvite;

import '../models/server_config.dart';
import '../services/background_time.dart';
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

  /// The connection to each mesh peer, by node ID (see
  /// [meshConnectionsOf]).
  final Map<String, MeshConnection> connections;

  /// Every device of this identity's networks, or null before the first
  /// list or when the native SDK has no device list.
  final List<NetworkDevice>? networkDevices;

  const MeshState({
    this.phase = MeshPhase.notSetUp,
    this.account,
    this.session,
    this.port = MeshPortStatus.stopped,
    this.error,
    this.connections = const {},
    this.networkDevices,
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

  /// The devices chat can run on: every Lemonade server of the device list
  /// that this device may connect to, whether the mesh has a path to it yet
  /// or not. The mesh port's devices when the native SDK has no list.
  List<MeshChatDevice> get chatDevices {
    final devices = networkDevices;
    if (devices == null) {
      return [for (final d in port.devices) (nodeId: d.nodeId, label: d.label, tunnelIp: '')];
    }
    final seen = <String>{};
    return [
      for (final d in devices)
        if (d.isInference && d.canConnect && !d.isSelf && seen.add(d.nodeId))
          (
            nodeId: d.nodeId,
            label: d.deviceName.isNotEmpty ? d.deviceName : d.nodeId,
            tunnelIp: d.tunnelIp.split('/').first,
          ),
    ];
  }

  /// The connection to chat device [nodeId]: connecting until the mesh
  /// lists it.
  MeshConnection connectionOf(String nodeId) =>
      connections[nodeId] ?? MeshConnection.connecting;

  int get onlineDevices =>
      chatDevices.where((d) => connectionOf(d.nodeId).isConnected).length;

  /// The chat devices as one line: how many are online, else whether the
  /// mesh still connects to one.
  String get devicesSummary {
    final online = onlineDevices;
    if (online > 0) return '$online online';
    final devices = chatDevices;
    if (devices.isEmpty) return 'no devices';
    return devices.any((d) => connectionOf(d.nodeId) == MeshConnection.connecting)
        ? 'connecting…'
        : 'devices offline';
  }

  /// The pill for [device] of [networkDevices] (see [meshDeviceConnection]).
  MeshConnection? deviceConnection(NetworkDevice device) =>
      meshDeviceConnection(device, connections: connections);

  MeshState copyWith({
    MeshPhase? phase,
    MeshAccount? account,
    MeshSession? session,
    MeshPortStatus? port,
    String? error,
    bool clearError = false,
    Map<String, MeshConnection>? connections,
    List<NetworkDevice>? networkDevices,
  }) =>
      MeshState(
        phase: phase ?? this.phase,
        account: account ?? this.account,
        session: session ?? this.session,
        port: port ?? this.port,
        error: clearError ? null : (error ?? this.error),
        connections: connections ?? this.connections,
        networkDevices: networkDevices ?? this.networkDevices,
      );
}

/// Mesh mode: the Lemonade Nexus device account and the running mesh.
///
/// [activate] / [deactivate] are driven by the app mode (appModeProvider);
/// this notifier does not watch the mode itself, because the mode in turn
/// follows [meshServerProvider]. The session and the mesh stay up while the
/// app is in the background. Only the loopback mesh port closes, after
/// [_portGrace] there, so another app cannot use it meanwhile; it reopens at
/// once when the app comes back.
/// A device chat can run on (see [MeshState.chatDevices]).
typedef MeshChatDevice = ({String nodeId, String label, String tunnelIp});

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
  StreamSubscription<MeshEvent>? _events;

  /// The native SDK reports mesh events: the state is read again when one
  /// arrives, not on a schedule.
  bool _hasEvents = false;

  /// A refresh runs; another one was asked for meanwhile.
  bool _refreshing = false;
  bool _refreshAgain = false;

  /// Since when the devices are looked for (see [_watchForDevices]).
  Stopwatch? _searchClock;
  DateTime? _lastRejoin;

  /// One connect at a time; later callers wait for it.
  Future<void>? _connecting;

  /// How long the mesh port stays open in the background: a quick switch to
  /// another app keeps a reply streaming.
  static const _portGrace = Duration(seconds: 30);
  bool _backgrounded = false;
  Timer? _portTimer;
  Future<void>? _portClosing;
  bool _portClosed = false;

  /// Right after a connect, refreshes the devices until one is online.
  Timer? _devicesPoll;

  /// How often [_watchForDevices] checks the search. Without mesh events it
  /// also reads the online state then; the read is local (no server call),
  /// so a short interval costs little.
  static const _devicesPollInterval = Duration(seconds: 1);

  /// When [refresh] last read the device list from the network. The list
  /// is a server call, so the polls after a connect read it at most every
  /// [_networkDevicesMaxAge]; the online state is read every time.
  DateTime? _networkDevicesAt;
  static const _networkDevicesMaxAge = Duration(seconds: 15);

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
    _events = service.meshEvents.listen(_onMeshEvent);
    _hasEvents = await service.hasMeshEvents();
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
  /// The session's [MeshSession.joinNotice] says when the device had a
  /// network of its own and the invite made it a member instead.
  Future<MeshSession> join(String inviteCode, String deviceName) => _setUp(
      MeshAccount.create(deviceName.trim()),
      inviteCode: normalizeInvite(inviteCode));

  Future<MeshSession> _setUp(MeshAccount account, {required String? inviteCode}) async {
    _active = true;
    state = MeshState(phase: MeshPhase.connecting, account: account);
    try {
      final service = await _ensureService();
      final session = await service.connect(account, inviteCode: inviteCode);
      final saved = account.copyWith(
          deviceName: session.deviceName,
          nameOnNetwork: session.deviceName,
          servers: session.servers,
          genesisKey: session.genesisKey,
          tier1Epoch: session.tier1Epoch,
          nodeId: session.nodeId);
      await saved.save();
      await _connected(service, saved, session);
      return session;
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
          session.deviceName != null ||
          !listEquals(account.servers, session.servers)) {
        saved = account.copyWith(
            deviceName: session.deviceName,
            nameOnNetwork: session.deviceName,
            servers: session.servers,
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
    _networkDevicesAt = null;
    await refresh();
    _portClosed = false;
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _heartbeat());
    unawaited(service.refreshPeers());
    _watchForDevices();
  }

  /// The SDK reported a change: read the state again. A device list event
  /// also reads the list from the network, whatever its age.
  void _onMeshEvent(MeshEvent event) {
    if (!_active || state.phase != MeshPhase.connected) return;
    if (event.kind == MeshEventKind.devices) _networkDevicesAt = null;
    unawaited(_refreshSoon());
  }

  /// One refresh at a time: events during a refresh run one more after it.
  Future<void> _refreshSoon() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        await refresh();
      } while (_refreshAgain && mounted);
    } finally {
      _refreshing = false;
    }
  }

  /// The devices come online over the first seconds after a connect, as the
  /// mesh reaches them. With mesh events each change is read as it comes;
  /// without them, refresh every [_devicesPollInterval] until a device is
  /// online, for at most 60 s.
  void _watchForDevices() {
    _devicesPoll?.cancel();
    _searchClock = Stopwatch()..start();
    final until = DateTime.now().add(const Duration(seconds: 60));
    _devicesPoll = Timer.periodic(_devicesPollInterval, (timer) async {
      if (!mounted ||
          state.phase != MeshPhase.connected ||
          state.onlineDevices > 0 ||
          DateTime.now().isAfter(until)) {
        timer.cancel();
        return;
      }
      if (!_hasEvents) await refresh();
    });
  }

  /// Re-reads the devices and the selection. The state changes only where
  /// the read found a change, so an unchanged poll rebuilds nothing.
  Future<void> refresh() async {
    final service = _service;
    if (service == null || state.phase != MeshPhase.connected) return;
    await _readMesh(service);
    final listedAt = _networkDevicesAt;
    if (listedAt != null &&
        DateTime.now().difference(listedAt) < _networkDevicesMaxAge) {
      return;
    }
    _networkDevicesAt = DateTime.now();
    try {
      // Null from a native SDK without the list: the panel keeps showing
      // the mesh port's devices only.
      final devices = await service.networkDevices();
      if (mounted && devices != null && !listEquals(devices, state.networkDevices)) {
        state = state.copyWith(networkDevices: devices);
      }
    } catch (e) {
      debugPrint('Mesh device list failed: $e');
    }
  }

  /// Reads the mesh port and the connection to each peer: local reads, no
  /// server call.
  Future<void> _readMesh(MeshService service) async {
    try {
      final port = await service.portStatus();
      if (mounted && port != state.port) state = state.copyWith(port: port);
    } catch (e) {
      debugPrint('Mesh status failed: $e');
    }
    try {
      final connections = await service.peers();
      if (mounted && !mapEquals(connections, state.connections)) {
        state = state.copyWith(connections: connections);
      }
    } catch (e) {
      debugPrint('Mesh peers failed: $e');
    }
    final clock = _searchClock;
    if (mounted && clock != null && state.onlineDevices > 0) {
      _searchClock = null;
      debugPrint('[mesh] a device is online after ${clock.elapsedMilliseconds} ms '
          '(${_hasEvents ? 'events' : 'polling'}; '
          '${state.connections.values.map((c) => c.name).join(', ')})');
    }
  }

  Future<void> _heartbeat() async {
    final service = _service;
    if (service == null || !_active || state.phase != MeshPhase.connected) return;
    if (await service.isUp()) {
      // With mesh events the state is already current; the heartbeat only
      // checks that the session is still up.
      if (!_hasEvents) await refresh();
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

  /// A single-use invite into this mesh: an 8-digit code (from servers that
  /// issue one) and the full link token, which name the same invite.
  Future<Invite> createInvite() async {
    final service = _service;
    if (service == null || state.phase != MeshPhase.connected) {
      throw const MeshException('Connect to your mesh first.');
    }
    return Invite.fromJson(await service.createInvite());
  }

  /// Removes this device from the mesh and forgets its identity.
  Future<void> leave() async {
    _poll?.cancel();
    _devicesPoll?.cancel();
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
    _devicesPoll?.cancel();
    _portTimer?.cancel();
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
      _backgrounded = true;
      if (state.phase == MeshPhase.connected) unawaited(BackgroundTime.begin());
      _portTimer?.cancel();
      _portTimer = Timer(_portGrace, _closePort);
    } else if (lifecycle == AppLifecycleState.resumed) {
      _backgrounded = false;
      unawaited(BackgroundTime.end());
      _portTimer?.cancel();
      _resume();
    }
  }

  void _closePort() {
    final service = _service;
    if (!_backgrounded || service == null || state.phase != MeshPhase.connected) {
      return;
    }
    _portClosed = true;
    _portClosing = service.closePort().catchError((Object e) {
      debugPrint('Mesh port close failed: $e');
    });
  }

  /// Back in the foreground: reopen the mesh port if it closed, and check
  /// that the session survived; a full reconnect only when it did not (iOS
  /// suspended the app for long, or the network dropped it meanwhile).
  Future<void> _resume() async {
    debugPrint('[mesh] resumed (port closed: $_portClosed)');
    await _portClosing;
    final service = _service;
    if (_backgrounded || !_active || !state.isSetUp) return;
    if (service == null || state.phase != MeshPhase.connected) {
      await _connect();
      return;
    }
    if (!await service.isUp()) {
      debugPrint('[mesh] the session did not survive the background: reconnecting');
      await _connect();
      return;
    }
    if (_portClosed) {
      try {
        await service.openPort(state.selection);
        _portClosed = false;
      } catch (e) {
        debugPrint('Mesh port reopen failed: $e');
        await _connect();
        return;
      }
    }
    // After a suspension the device list is stale: fetch it now, and read
    // the peers again until one is back.
    unawaited(service.refreshPeers());
    await refresh();
    _watchForDevices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _devicesPoll?.cancel();
    _portTimer?.cancel();
    _moves?.cancel();
    _events?.cancel();
    _service?.close();
    super.dispose();
  }
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
