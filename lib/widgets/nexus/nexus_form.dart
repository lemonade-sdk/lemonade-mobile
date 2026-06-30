import 'package:flutter/material.dart';

import '../../themes/nexus_tokens.dart';

/// Small form primitives shared by the agent / tool / knowledge editors.

InputDecoration nexusInput(BuildContext context, String hint) {
  final t = context.nexus;
  return InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: t.bg,
    hintStyle: TextStyle(color: t.faint, fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: t.line2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: t.line2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: t.accent),
    ),
  );
}

/// A labeled text field.
class NexusField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final int lines;
  final TextInputType? keyboard;
  const NexusField({
    super.key,
    required this.label,
    required this.controller,
    this.hint = '',
    this.lines = 1,
    this.keyboard,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: t.faint)),
          ),
          TextField(
            controller: controller,
            minLines: lines,
            maxLines: lines,
            keyboardType: keyboard,
            style: TextStyle(fontSize: 14, color: t.text),
            decoration: nexusInput(context, hint),
          ),
        ],
      ),
    );
  }
}

/// A toggle row.
class NexusToggleTile extends StatelessWidget {
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  const NexusToggleTile({
    super.key,
    required this.label,
    this.sub,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 14, color: t.text)),
              if (sub != null)
                Text(sub!, style: TextStyle(fontSize: 11, color: t.muted)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }
}

/// A simple dark-styled scaffold for the pushed editor/list screens.
class NexusPage extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final Widget body;
  const NexusPage(
      {super.key, required this.title, required this.body, this.actions});

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg2,
        title: Text(title,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: t.text)),
        iconTheme: IconThemeData(color: t.muted),
        actions: actions,
      ),
      body: body,
    );
  }
}

/// A primary full-width button.
class NexusButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final Color? color;
  const NexusButton(
      {super.key, required this.label, this.onTap, this.busy = false, this.color});

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
            color: color ?? t.accent, borderRadius: BorderRadius.circular(13)),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
      ),
    );
  }
}
