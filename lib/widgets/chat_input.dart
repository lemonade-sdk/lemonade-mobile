import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lemonade_mobile/providers/chat_provider.dart';
import 'package:lemonade_mobile/constants/messages.dart';
import 'package:lemonade_mobile/utils/image_utils.dart';

class ChatInput extends ConsumerWidget {
  final ScrollController? scrollController;

  const ChatInput({super.key, this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ChatInputWidget(ref: ref, scrollController: scrollController);
  }
}

class _ChatInputWidget extends StatefulWidget {
  final WidgetRef ref;
  final ScrollController? scrollController;

  const _ChatInputWidget({required this.ref, this.scrollController});

  @override
  State<_ChatInputWidget> createState() => _ChatInputWidgetState();
}

class _ChatInputWidgetState extends State<_ChatInputWidget> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  final List<String> _attachedImagePaths = [];

  // Command autocomplete
  final List<String> _availableCommands = ['/image', '/draw', '/small', '/medium', '/large'];
  bool _showCommandSuggestions = false;
  String _currentCommandPrefix = '';
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _hideOverlay(); // Clean up overlay
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;

    // Check for command suggestions
    if (text.startsWith('/')) {
      final parts = text.split(' ');
      if (parts.length == 1) {
        // Show suggestions for incomplete commands
        final prefix = parts[0];
        final filteredCommands = _availableCommands
            .where((cmd) => cmd.startsWith(prefix))
            .toList();
        if (filteredCommands.isNotEmpty && _overlayEntry == null) {
          _showOverlay();
        } else if (filteredCommands.isEmpty && _overlayEntry != null) {
          _hideOverlay();
        }
        setState(() {
          _showCommandSuggestions = filteredCommands.isNotEmpty;
          _currentCommandPrefix = prefix;
        });
      } else {
        // Hide suggestions when command is complete
        _hideOverlay();
        setState(() {
          _showCommandSuggestions = false;
        });
      }
    } else {
      _hideOverlay();
      setState(() {
        _showCommandSuggestions = false;
      });
    }

    setState(() {}); // Rebuild to update hint text
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: 16, // Small margin from screen edges
        right: 16, // Small margin from screen edges
        top: kToolbarHeight + 16, // Below the app bar
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(25), // Pill shape
          color: Theme.of(context).colorScheme.surface,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25), // Pill shape
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableCommands
                      .where((cmd) => cmd.startsWith(_currentCommandPrefix))
                      .map((command) => InkWell(
                            onTap: () => _selectCommand(command),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                command,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _selectCommand(String command) {
    final currentText = _controller.text;
    final parts = currentText.split(' ');
    if (parts.isNotEmpty) {
      parts[0] = command;
      _controller.text = parts.join(' ') + (parts.length > 1 ? '' : ' ');
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }

    // Keep dropdown open if selecting /image or /draw (to allow size commands)
    final shouldKeepOpen = command == '/image' || command == '/draw';

    setState(() {
      _showCommandSuggestions = shouldKeepOpen;
      if (shouldKeepOpen) {
        _currentCommandPrefix = '/'; // Show all commands again
      }
    });
    _focusNode.requestFocus();
  }



  Future<void> _pickImage(ImageSource source) async {
    try {
      // Let image_picker handle permissions automatically
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );

      if (image != null && mounted) {
        final bytes = await image.readAsBytes();

        if (bytes.isNotEmpty) {
          // Convert to base64 immediately (like JavaScript fileToBase64)
          final base64String = base64Encode(bytes);
          final mimeType = ImageUtils.getMimeTypeFromPath(image.path);
          final dataUrl = 'data:$mimeType;base64,$base64String';

          setState(() {
            _attachedImagePaths.add(dataUrl);
          });
          print('Image converted to base64 data URL: ${dataUrl.length} characters');
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to read image: file is empty')),
            );
          }
        }
      }
    } catch (e) {
      print('Error in _pickImage: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppMessages.imagePickError(e.toString()))),
        );
      }
    }
  }

  void _showImageSourceDialog() {
    if (Platform.isMacOS) {
      // On macOS, use file picker instead of gallery
      _pickImageFromFile();
    } else {
      // On mobile platforms, show camera/gallery options
      showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _pickImageFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty && mounted) {
        final file = result.files.first;
        final bytes = await File(file.path!).readAsBytes();

        if (bytes.isNotEmpty) {
          // Convert to base64 immediately (like JavaScript fileToBase64)
          final base64String = base64Encode(bytes);
          final mimeType = ImageUtils.getMimeTypeFromPath(file.path!);
          final dataUrl = 'data:$mimeType;base64,$base64String';

          setState(() {
            _attachedImagePaths.add(dataUrl);
          });
          print('Image converted to base64 data URL: ${dataUrl.length} characters');
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to read image: file is empty')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppMessages.imageSelectError(e.toString()))),
        );
      }
    }
  }

  void _sendMessage() async {
    final message = _controller.text.trim();
    if ((message.isEmpty && _attachedImagePaths.isEmpty) || _isLoading) return;

    final imagePaths = List<String>.from(_attachedImagePaths);
    setState(() => _isLoading = true);
    _controller.clear();
    _attachedImagePaths.clear();

    try {
      await widget.ref.read(chatProvider.notifier).sendMessage(message, imagePaths: imagePaths, scrollController: widget.scrollController);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _focusNode.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: IconButton(
              onPressed: _isLoading ? null : _showImageSourceDialog,
              icon: Icon(
                Icons.image,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              tooltip: 'Add image',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: _attachedImagePaths.isNotEmpty
                      ? (_controller.text.startsWith('/') ? AppMessages.imageCommandHint : AppMessages.messageWithImageHint)
                      : (_controller.text.startsWith('/') ? AppMessages.imageCommandHint : AppMessages.defaultMessageHint),
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
                textInputAction: TextInputAction.send,
                maxLines: 5,
                minLines: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _isLoading ? null : _sendMessage,
              icon: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : Icon(
                      Icons.send,
                      color: theme.colorScheme.onPrimary,
                    ),
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }
}
