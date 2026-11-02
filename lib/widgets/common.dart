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

/// Nuancier : couleurs proposées + bouton « autre couleur » (code hexadécimal ou curseurs).
const colorSwatches = <int>[
  0xFFFFFFFF,
  0xFF111111,
  0xFF37474F,
  0xFF90A4AE,
  0xFF009E49,
  0xFF0B6B3A,
  0xFF00897B,
  0xFF1E4FA1,
  0xFF0D1B3E,
  0xFF1A237E,
  0xFF6A1B9A,
  0xFF8E1B2E,
  0xFFC62828,
  0xFFEF2B2D,
  0xFFE65100,
  0xFFFFA000,
  0xFFFCD116,
  0xFFC9A646,
  0xFF795548,
  0xFF90CAF9,
];

class ColorRow extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final List<int> extra;
  final bool allowNone;
  final bool isNone;
  final VoidCallback? onNone;

  const ColorRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.extra = const [],
    this.allowNone = false,
    this.isNone = false,
    this.onNone,
  });

  @override
  Widget build(BuildContext context) {
    final colors = <int>{...extra, ...colorSwatches, value}.toList();
    Widget dot(Widget child, bool sel, VoidCallback tap, {Color? color}) => InkWell(
          onTap: tap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: sel ? Theme.of(context).colorScheme.onSurface : Colors.black26,
                width: sel ? 3 : 1,
              ),
            ),
            child: child,
          ),
        );
    return Wrap(spacing: 6, runSpacing: 6, children: [
      if (allowNone) dot(const Icon(Icons.block, size: 16, color: Colors.grey), isNone, () => onNone?.call()),
      for (final c in colors) dot(const SizedBox(), !isNone && c == value, () => onChanged(c), color: Color(c)),
      Tooltip(
        message: 'Autre couleur',
        child: dot(const Icon(Icons.colorize, size: 16), false, () async {
          final c = await pickColor(context, value);
          if (c != null) onChanged(c);
        }),
      ),
    ]);
  }
}

String colorHex(int c) => '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

int? parseColorHex(String s) {
  final h = s.trim().replaceAll('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(h)) return null;
  return 0xFF000000 | int.parse(h, radix: 16);
}

/// Choix libre d'une couleur : teinte, saturation, luminosité ou code #RRGGBB.
Future<int?> pickColor(BuildContext context, int initial) {
  var hsl = HSLColor.fromColor(Color(initial));
  final hex = TextEditingController(text: colorHex(initial));
  return showDialog<int>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final color = hsl.toColor();
      void update(HSLColor v) => set(() {
            hsl = v;
            hex.text = colorHex(v.toColor().toARGB32());
          });
      return AlertDialog(
        title: const Text('Choisir une couleur'),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Teinte'),
            Slider(value: hsl.hue, max: 360, onChanged: (v) => update(hsl.withHue(v))),
            const Text('Saturation'),
            Slider(value: hsl.saturation, onChanged: (v) => update(hsl.withSaturation(v))),
            const Text('Luminosité'),
            Slider(value: hsl.lightness, onChanged: (v) => update(hsl.withLightness(v))),
            TextField(
              controller: hex,
              decoration: const InputDecoration(labelText: 'Code couleur', hintText: '#E31E24'),
              onChanged: (v) {
                final p = parseColorHex(v);
                if (p != null) set(() => hsl = HSLColor.fromColor(Color(p)));
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, hsl.toColor().toARGB32()), child: const Text('Choisir')),
        ],
      );
    }),
  );
}
