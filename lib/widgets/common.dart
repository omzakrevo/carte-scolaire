import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Ouvre le sélecteur de fichiers et renvoie le nom et le contenu du fichier
/// choisi, ou `null` si l'utilisateur annule.
Future<(String, Uint8List)?> pickOneFile({FileType type = FileType.any, List<String>? extensions}) async {
  final f = await FilePicker.pickFile(type: type, allowedExtensions: extensions);
  if (f == null) return null;
  return (f.name, await f.readAsBytes());
}

/// Champ texte qui garde son propre contrôleur (valeur initiale + callback).
class TextSetting extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final TextInputType? keyboard;

  const TextSetting({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.keyboard,
  });

  @override
  State<TextSetting> createState() => _TextSettingState();
}

class _TextSettingState extends State<TextSetting> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(TextSetting old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text && !_focus.hasFocus) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        focusNode: _focus,
        keyboardType: widget.keyboard,
        decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
        onChanged: widget.onChanged,
      );
}

/// Bloc titré pour regrouper des réglages.
class Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? trailing;

  const Section({super.key, required this.title, this.subtitle, required this.children, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      color: t.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: t.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (subtitle != null)
                  Text(subtitle!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ]),
            ),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 12),
          ...children,
        ]),
      ),
    );
  }
}

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      behavior: SnackBarBehavior.floating,
    ));
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Confirmer'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}
