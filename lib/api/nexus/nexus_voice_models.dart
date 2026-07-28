/// DTOs for the Nexus gateway Voice API (`/api/v1/voice/*`). Field names mirror
/// the C# `*View` records (System.Text.Json camelCase). All parsers tolerate
/// missing/null fields so a partial payload never throws.
library;

import 'dart:convert';

import 'json_utils.dart';

DateTime? _date(dynamic v) => jsonDate(v);
int? _int(dynamic v) => jsonInt(v);
String _str(dynamic v) => jsonStr(v);

class NexusCall {
  final String callRef;
  final String direction; // Inbound | Outbound | Internal
  final String state; // Ringing | Answered | Held | Parked | Ended | Failed …
  final String fromNumber;
  final String toNumber;
  final int? extensionId;
  final int? parkingSlotNumber;
  final String? parentCallRef;
  final DateTime? startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final int billableSeconds;
  final String? hangupCause;
  final double cost;

  const NexusCall({
    required this.callRef,
    required this.direction,
    required this.state,
    required this.fromNumber,
    required this.toNumber,
    this.extensionId,
    this.parkingSlotNumber,
    this.parentCallRef,
    this.startedAt,
    this.answeredAt,
    this.endedAt,
    this.billableSeconds = 0,
    this.hangupCause,
    this.cost = 0,
  });

  bool get isInbound => direction.toLowerCase() == 'inbound';
  bool get isActive {
    final s = state.toLowerCase();
    return s == 'ringing' || s == 'answered' || s == 'held' || s == 'parked';
  }

  factory NexusCall.fromJson(Map<String, dynamic> j) => NexusCall(
        callRef: _str(j['callRef']),
        direction: _str(j['direction']),
        state: _str(j['state']),
        fromNumber: _str(j['fromNumber']),
        toNumber: _str(j['toNumber']),
        extensionId: _int(j['extensionId']),
        parkingSlotNumber: _int(j['parkingSlotNumber']),
        parentCallRef: j['parentCallRef']?.toString(),
        startedAt: _date(j['startedAt']),
        answeredAt: _date(j['answeredAt']),
        endedAt: _date(j['endedAt']),
        billableSeconds: _int(j['billableSeconds']) ?? 0,
        hangupCause: j['hangupCause']?.toString(),
        cost: (j['cost'] is num) ? (j['cost'] as num).toDouble() : 0,
      );
}

/// A DID / phone number (`NumberView`).
class NexusNumber {
  final int id;
  final String number;
  final String status;
  final String routeType; // IvrFlow | Extension | RingAll | Voicemail | ForwardExternal
  final int? ivrFlowId;
  final int? extensionId;
  final String? forwardE164;
  final String label;
  final int sellMonthlyCents;
  final bool smsEnabled;
  final bool e911Provisioned;
  final DateTime? createdAt;

  const NexusNumber({
    required this.id,
    required this.number,
    required this.status,
    required this.routeType,
    this.ivrFlowId,
    this.extensionId,
    this.forwardE164,
    this.label = '',
    this.sellMonthlyCents = 0,
    this.smsEnabled = false,
    this.e911Provisioned = false,
    this.createdAt,
  });

  factory NexusNumber.fromJson(Map<String, dynamic> j) => NexusNumber(
        id: _int(j['id']) ?? 0,
        number: _str(j['number']),
        status: _str(j['status']),
        routeType: _str(j['routeType']),
        ivrFlowId: _int(j['ivrFlowId']),
        extensionId: _int(j['extensionId']),
        forwardE164: j['forwardE164']?.toString(),
        label: _str(j['label']),
        sellMonthlyCents: _int(j['sellMonthlyCents']) ?? 0,
        smsEnabled: j['smsEnabled'] == true,
        e911Provisioned: j['e911Provisioned'] == true,
        createdAt: _date(j['createdAt']),
      );
}

/// A number available to order from voip.ms.
class NexusAvailableNumber {
  final String number;
  final String rateCenter;
  final String state;
  final int sellMonthlyCents;

  const NexusAvailableNumber({
    required this.number,
    this.rateCenter = '',
    this.state = '',
    this.sellMonthlyCents = 0,
  });

  factory NexusAvailableNumber.fromJson(Map<String, dynamic> j) =>
      NexusAvailableNumber(
        number: _str(j['number']),
        rateCenter: _str(j['rateCenter']),
        state: _str(j['state']),
        sellMonthlyCents: _int(j['sellMonthlyCents']) ?? 0,
      );

  /// "$1.99/mo" — what THIS account pays (carrier never exposed).
  String get priceLabel => '\$${(sellMonthlyCents / 100).toStringAsFixed(2)}/mo';
}

/// Result of GET /voice/numbers/available — the matches plus which segment the
/// server actually applied and whether the Personal/Business/Both switch should
/// render (`switchEnabled` false → Personal account: hide the switch).
class NexusNumberSearchResult {
  final List<NexusAvailableNumber> numbers;
  final String segment; // personal | business | both
  final bool switchEnabled;

  const NexusNumberSearchResult({
    this.numbers = const [],
    this.segment = '',
    this.switchEnabled = false,
  });

  factory NexusNumberSearchResult.fromJson(Map<String, dynamic> j) =>
      NexusNumberSearchResult(
        numbers: ((j['numbers'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(NexusAvailableNumber.fromJson)
            .toList(),
        segment: _str(j['segment']),
        switchEnabled: j['switchEnabled'] == true,
      );
}

/// A SIP extension (`ExtensionView`).
class NexusExtension {
  final int id;
  final String number;
  final String displayName;
  final String? userId;
  final bool enabled;
  final int ringTimeoutSeconds;
  final bool voicemailEnabled;
  final String? forwardMode;
  final String? forwardTarget;
  final DateTime? createdAt;

  const NexusExtension({
    required this.id,
    required this.number,
    required this.displayName,
    this.userId,
    this.enabled = true,
    this.ringTimeoutSeconds = 20,
    this.voicemailEnabled = true,
    this.forwardMode,
    this.forwardTarget,
    this.createdAt,
  });

  /// The design's status line: registration is implied by `enabled` here; the
  /// API doesn't surface live SIP registration in the list view.
  String get statusLabel => enabled ? 'Registered' : 'Disabled';

  factory NexusExtension.fromJson(Map<String, dynamic> j) => NexusExtension(
        id: _int(j['id']) ?? 0,
        number: _str(j['number']),
        displayName: _str(j['displayName']),
        userId: j['userId']?.toString(),
        enabled: j['enabled'] != false,
        ringTimeoutSeconds: _int(j['ringTimeoutSeconds']) ?? 20,
        voicemailEnabled: j['voicemailEnabled'] != false,
        forwardMode: j['forwardMode']?.toString(),
        forwardTarget: j['forwardTarget']?.toString(),
        createdAt: _date(j['createdAt']),
      );
}

/// Result of creating an extension — includes the one-time SIP password.
class NexusExtensionCreated {
  final NexusExtension extension;
  final String sipPassword;
  const NexusExtensionCreated(this.extension, this.sipPassword);
}

/// An IVR flow (`FlowView`). [flowJson] is null in list responses, populated by
/// the single-flow GET.
class NexusFlow {
  final int id;
  final String name;
  final int version;
  final bool enabled;
  final Map<String, dynamic>? flowJson;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const NexusFlow({
    required this.id,
    required this.name,
    this.version = 1,
    this.enabled = false,
    this.flowJson,
    this.createdAt,
    this.updatedAt,
  });

  /// `published` in the design's vocabulary.
  bool get isPublished => enabled;

  /// Node count for the "N nodes" subtitle.
  int get nodeCount {
    final nodes = flowJson?['nodes'];
    if (nodes is Map) return nodes.length;
    return 0;
  }

  factory NexusFlow.fromJson(Map<String, dynamic> j) {
    final raw = j['flowJson'];
    Map<String, dynamic>? parsed;
    if (raw is Map<String, dynamic>) {
      parsed = raw;
    } else if (raw is String && raw.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) parsed = decoded;
      } catch (_) {}
    }
    return NexusFlow(
      id: _int(j['id']) ?? 0,
      name: _str(j['name']),
      version: _int(j['version']) ?? 1,
      enabled: j['enabled'] == true,
      flowJson: parsed,
      createdAt: _date(j['createdAt']),
      updatedAt: _date(j['updatedAt']),
    );
  }
}

/// A voicemail message (`MessageView`).
class NexusVoicemail {
  final int id;
  final int? extensionId;
  final String fromNumber;
  final int durationSeconds;
  final String? transcriptText;
  final bool isRead;
  final DateTime? createdAt;

  const NexusVoicemail({
    required this.id,
    this.extensionId,
    required this.fromNumber,
    this.durationSeconds = 0,
    this.transcriptText,
    this.isRead = false,
    this.createdAt,
  });

  factory NexusVoicemail.fromJson(Map<String, dynamic> j) => NexusVoicemail(
        id: _int(j['id']) ?? 0,
        extensionId: _int(j['extensionId']),
        fromNumber: _str(j['fromNumber']),
        durationSeconds: _int(j['durationSeconds']) ?? 0,
        transcriptText: j['transcriptText']?.toString(),
        isRead: j['isRead'] == true,
        createdAt: _date(j['createdAt']),
      );
}

/// `GET /voice/dashboard` aggregates.
class NexusVoiceDashboard {
  final String accountName;
  final int callsToday;
  final int numberCount;
  final int minutesUsed;
  final int minutesLimit;
  final List<NexusCall> recentCalls;

  const NexusVoiceDashboard({
    this.accountName = '',
    this.callsToday = 0,
    this.numberCount = 0,
    this.minutesUsed = 0,
    this.minutesLimit = 0,
    this.recentCalls = const [],
  });

  int get minutesLeft =>
      minutesLimit <= 0 ? 0 : (minutesLimit - minutesUsed).clamp(0, minutesLimit);

  factory NexusVoiceDashboard.fromJson(Map<String, dynamic> j) =>
      NexusVoiceDashboard(
        accountName: _str(j['accountName']),
        callsToday: _int(j['callsToday']) ?? 0,
        numberCount: _int(j['numberCount']) ?? 0,
        minutesUsed: _int(j['minutesUsed']) ?? 0,
        minutesLimit: _int(j['minutesLimit']) ?? 0,
        recentCalls: ((j['recentCalls'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(NexusCall.fromJson)
            .toList(),
      );
}

/// `GET /voice/team` member.
class NexusTeamMember {
  final int id;
  final String email;
  final String displayName;
  final String role; // Member | Admin | Owner
  final DateTime? joinedAt;

  const NexusTeamMember({
    required this.id,
    this.email = '',
    this.displayName = '',
    this.role = 'Member',
    this.joinedAt,
  });

  factory NexusTeamMember.fromJson(Map<String, dynamic> j) => NexusTeamMember(
        id: _int(j['id']) ?? 0,
        email: _str(j['email']),
        displayName: _str(j['displayName']),
        role: _str(j['role']).isEmpty ? 'Member' : _str(j['role']),
        joinedAt: _date(j['joinedAt']),
      );
}

/// `GET/PUT /voice/settings` — account voice settings.
class NexusVoiceSettings {
  final bool enabled;
  final int channelLimit;
  final String timeZone;
  final String callerIdName;
  final bool recordCalls;
  final String callTaskPromptTemplate;
  final String subAccount;
  final String nodeName;
  final bool nodeHealthy;
  final String sipHost;

  const NexusVoiceSettings({
    this.enabled = false,
    this.channelLimit = 0,
    this.timeZone = '',
    this.callerIdName = '',
    this.recordCalls = false,
    this.callTaskPromptTemplate = '',
    this.subAccount = '',
    this.nodeName = '',
    this.nodeHealthy = false,
    this.sipHost = '',
  });

  factory NexusVoiceSettings.fromJson(Map<String, dynamic> j) =>
      NexusVoiceSettings(
        enabled: j['enabled'] == true,
        channelLimit: _int(j['channelLimit']) ?? 0,
        timeZone: _str(j['timeZone']),
        callerIdName: _str(j['callerIdName']),
        recordCalls: j['recordCalls'] == true,
        callTaskPromptTemplate: _str(j['callTaskPromptTemplate']),
        subAccount: _str(j['subAccount']),
        nodeName: _str(j['nodeName']),
        nodeHealthy: j['nodeHealthy'] == true,
        sipHost: _str(j['sipHost']),
      );
}

/// A live event from the `/voice/events` WebSocket (`CallEvents.Payload`).
class NexusCallEvent {
  final String event; // call.ringing | call.answered | call.held | call.parked | call.ended | voicemail.new
  final String callRef;
  final String direction;
  final String fromNumber;
  final String toNumber;
  final String state;
  final int? extensionId;
  final int? durationSeconds;

  const NexusCallEvent({
    required this.event,
    required this.callRef,
    this.direction = '',
    this.fromNumber = '',
    this.toNumber = '',
    this.state = '',
    this.extensionId,
    this.durationSeconds,
  });

  bool get isEnded => event == 'call.ended';

  factory NexusCallEvent.fromJson(Map<String, dynamic> j) => NexusCallEvent(
        event: _str(j['event']),
        callRef: _str(j['callRef']),
        direction: _str(j['direction']),
        fromNumber: _str(j['fromNumber']),
        toNumber: _str(j['toNumber']),
        state: _str(j['state']),
        extensionId: _int(j['extensionId']),
        durationSeconds: _int(j['durationSeconds']),
      );
}
