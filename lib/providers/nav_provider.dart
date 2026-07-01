import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The six bottom-nav destinations.
enum NexusTab { chat, projects, calls, pbx, docs, settings }

/// PBX sub-navigation.
enum PbxSection { numbers, extensions, flows, voicemail, history }

/// Currently selected bottom-nav tab.
final navTabProvider = StateProvider<NexusTab>((ref) => NexusTab.chat);

/// Currently selected PBX sub-tab.
final pbxTabProvider = StateProvider<PbxSection>((ref) => PbxSection.numbers);

/// Identifies which full-screen overlay (if any) is mounted above the shell.
/// Only one is visible at a time except the auth gate, which is driven directly
/// by [appModeProvider] + signed-in state rather than this controller.
enum NexusOverlayKind {
  none,
  conversationsDrawer,
  modeSheet,
  subSheet,
  liveCall,
  flowEditor,
  numberRouting,
  imageLightbox,
}

/// Lightweight payload bag for the active overlay. Fields are populated only for
/// the overlays that need them.
class NexusOverlayState {
  final NexusOverlayKind kind;

  /// liveCall: the AI call task being watched.
  final int? taskId;

  /// flowEditor: the IVR flow id being edited (null = new flow).
  final int? flowId;

  /// numberRouting: the DID/number id being routed.
  final int? numberId;

  /// imageLightbox: decoded image bytes + a label/caption.
  final Uint8List? imageBytes;
  final String? imageLabel;
  final String? imageCaption;

  /// subSheet: 'plan' or 'billing'.
  final String subSheetSection;

  const NexusOverlayState({
    this.kind = NexusOverlayKind.none,
    this.taskId,
    this.flowId,
    this.numberId,
    this.imageBytes,
    this.imageLabel,
    this.imageCaption,
    this.subSheetSection = 'plan',
  });

  bool get isOpen => kind != NexusOverlayKind.none;
}

class _OverlayNotifier extends StateNotifier<NexusOverlayState> {
  _OverlayNotifier() : super(const NexusOverlayState());

  void close() => state = const NexusOverlayState();

  void openConversations() =>
      state = const NexusOverlayState(kind: NexusOverlayKind.conversationsDrawer);

  void openModeSheet() =>
      state = const NexusOverlayState(kind: NexusOverlayKind.modeSheet);

  void openSubSheet({String section = 'plan'}) => state =
      NexusOverlayState(kind: NexusOverlayKind.subSheet, subSheetSection: section);

  void openLiveCall(int taskId) =>
      state = NexusOverlayState(kind: NexusOverlayKind.liveCall, taskId: taskId);

  void openFlowEditor({int? flowId}) =>
      state = NexusOverlayState(kind: NexusOverlayKind.flowEditor, flowId: flowId);

  void openNumberRouting(int numberId) => state =
      NexusOverlayState(kind: NexusOverlayKind.numberRouting, numberId: numberId);

  void openLightbox({
    Uint8List? bytes,
    String? label,
    String? caption,
  }) =>
      state = NexusOverlayState(
        kind: NexusOverlayKind.imageLightbox,
        imageBytes: bytes,
        imageLabel: label,
        imageCaption: caption,
      );
}

/// Controller for the single active full-screen overlay.
final overlayProvider =
    StateNotifierProvider<_OverlayNotifier, NexusOverlayState>(
        (ref) => _OverlayNotifier());
