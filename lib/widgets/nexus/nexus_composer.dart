import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/chat_provider.dart';
import '../../themes/nexus_tokens.dart';
import '../../utils/friendly_error.dart';
import '../voice_input_sheet.dart';

/// Design-faithful chat composer: attach (+), input pill with inline mic, and a
/// send button. Wires to the existing `chatProvider.sendMessage`. Replaces the
/// legacy ChatInput on the Chat tab.
class NexusComposer extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  const NexusComposer({super.key, this.scrollController});

  @override
  ConsumerState<NexusComposer> createState() => _NexusComposerState();
}

class _NexusComposerState extends ConsumerState<NexusComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _picker = ImagePicker();
  final List<String> _attached = [];

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  /// The composer "+" — attach an image. Offers the camera (mobile), the photo
  /// library (mobile), and a file picker (works on desktop/macOS where the
  /// gallery/camera sources are a no-op).
  Future<void> _attach() async {
    final t = context.nexus;
    // The camera source is only meaningful on a real mobile device; hide it on
    // desktop where it would just no-op.
    final showCamera = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: t.bg2,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showCamera)
              ListTile(
                leading: Icon(Icons.camera_alt_outlined, color: t.accent),
                title: Text('Take photo', style: TextStyle(color: t.text)),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: t.accent),
              title: Text('Photo library', style: TextStyle(color: t.text)),
              onTap: () => Navigator.pop(ctx, 'photo'),
            ),
            ListTile(
              leading: Icon(Icons.insert_drive_file_outlined, color: t.accent),
              title: Text('Choose image file', style: TextStyle(color: t.text)),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (choice == 'camera') {
      await _takePhoto();
    } else if (choice == 'photo') {
      await _pickFromGallery();
    } else if (choice == 'file') {
      await _pickFile();
    }
  }

  Future<void> _takePhoto() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.camera);
      if (picked != null) setState(() => _attached.add(picked.path));
    } catch (e) {
      _toast(friendlyError(e, action: 'open the camera'));
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) setState(() => _attached.add(picked.path));
    } catch (e) {
      _toast(friendlyError(e, action: 'open your photo library'));
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = result?.files.singleOrNull?.path;
      if (path != null) setState(() => _attached.add(path));
    } catch (e) {
      _toast(friendlyError(e, action: 'open your files'));
    }
  }

  void _send() {
    if (ref.read(chatStreamingProvider)) return; // one turn at a time
    final text = _controller.text.trim();
    if (text.isEmpty && _attached.isEmpty) return;
    // Validate BEFORE clearing so a blocked send (no server, no model,
    // image on a text-only model) keeps the user's text and attachments.
    final blocked = ref
        .read(chatProvider.notifier)
        .sendBlockedReason(hasImages: _attached.isNotEmpty);
    if (blocked != null) {
      _toast(blocked);
      return;
    }
    ref.read(chatProvider.notifier).sendMessage(
          text,
          imagePaths: _attached.isEmpty ? null : List.of(_attached),
          scrollController: widget.scrollController,
        );
    _controller.clear();
    setState(() => _attached.clear());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return Container(
      color: t.bg,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_attached.isNotEmpty)
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _attached.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(File(_attached[i]),
                                width: 56, height: 56, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: -4,
                            right: -4,
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _attached.removeAt(i)),
                              child: Container(
                                decoration: BoxDecoration(
                                    color: t.bg2,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: t.line2)),
                                child: Icon(Icons.close,
                                    size: 14, color: t.muted),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _squareButton(
                context,
                icon: Icons.add,
                bg: t.surface,
                border: t.line2,
                iconColor: t.muted,
                onTap: _attach,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  // Clip so selection/focus paint can't square-cut the stroke
                  // (the classic "round over square" composer glitch).
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: t.surface,
                    // Squircle that matches the attach/send buttons (radius 14)
                    // rather than a full pill that fights multi-line growth.
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.line2),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          style: TextStyle(fontSize: 14.5, color: t.text),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 11),
                            hintText: 'Message Lemonade…',
                            hintStyle:
                                TextStyle(color: t.faint, fontSize: 14.5),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => VoiceInputSheet.show(context,
                            chatScrollController: widget.scrollController),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.mic_none,
                              size: 20, color: t.accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Builder(builder: (context) {
                final streaming = ref.watch(chatStreamingProvider);
                return GestureDetector(
                  onTap: streaming
                      ? () => ref.read(chatProvider.notifier).stopStreaming()
                      : _send,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: t.accent,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: t.accent.withValues(alpha: 0.4),
                            blurRadius: 14,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Icon(streaming ? Icons.stop : Icons.send,
                        size: 18, color: Colors.white),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _squareButton(BuildContext context,
      {required IconData icon,
      required Color bg,
      required Color border,
      required Color iconColor,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
    );
  }
}
