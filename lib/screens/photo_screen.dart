import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../designs/card_designs.dart';
import '../main.dart' show isDesktop;
import '../models.dart';
import '../services/phone_bridge.dart';
import '../services/photo_utils.dart';
import '../widgets/common.dart';
import 'students_screen.dart' show editStudent;

class PhotoScreen extends StatefulWidget {
  final VoidCallback onGoToStudents;
  final VoidCallback onNext;
  const PhotoScreen({super.key, required this.onGoToStudents, required this.onNext});

  @override
  State<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<PhotoScreen> {
  PhoneBridge? _bridge;
  bool _autoAdvance = true;
  bool _working = false;
  Timer? _tick;
  final _focus = FocusNode();

  @override
  void dispose() {
    _bridge?.stop();
    _tick?.cancel();
    _focus.dispose();
    super.dispose();
  }

  AppState get _state => AppScope.read(context);

  Future<void> _applyPhoto(Student s, Uint8List bytes, {bool advance = false}) async {
    setState(() => _working = true);
    try {
      final prepared = await preparePhoto(bytes);
      _state.setPhoto(s, prepared);
      if (advance && _state.currentIndex < _state.students.length - 1) _state.move(1);
    } catch (e) {
      if (mounted) toast(context, 'Photo illisible. Réessayez avec une image JPEG ou PNG.', error: true);
      rethrow;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _pickFile() async {
    final s = _state.current;
    if (s == null) return;
    Uint8List? bytes;
    try {
      if (isDesktop) {
        final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
        bytes = r?.files.single.bytes;
      } else {
        final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1800);
        bytes = await x?.readAsBytes();
      }
    } catch (e) {
      if (mounted) toast(context, 'Impossible d\'ouvrir les images : $e', error: true);
      return;
    }
    if (bytes != null) await _applyPhoto(s, bytes).catchError((_) {});
  }

  Future<void> _takePhoto() async {
    final s = _state.current;
    if (s == null) return;
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1800,
        imageQuality: 92,
      );
      if (x == null) return;
      await _applyPhoto(s, await x.readAsBytes()).catchError((_) {});
    } catch (e) {
      if (mounted) toast(context, 'Caméra indisponible : vérifiez l\'autorisation dans les réglages.', error: true);
    }
  }

  Future<void> _startBridge() async {
    if (_bridge == null) {
      final b = PhoneBridge(
        state: () {
          final st = _state;
          final c = st.current;
          return {
            'index': st.currentIndex,
            'total': st.students.length,
            'name': c?.fullName ?? '',
            'classe': c?.classe ?? '',
            'hasPhoto': c?.photo != null,
          };
        },
        onPhoto: (bytes) async {
          final c = _state.current;
          if (c == null) throw StateError('Aucun élève sélectionné');
          await _applyPhoto(c, bytes, advance: _autoAdvance);
        },
        onNavigate: (d) => _state.move(d),
      );
      try {
        await b.start();
      } catch (e) {
        if (mounted) toast(context, 'Impossible de démarrer la liaison : $e', error: true);
        return;
      }
      _tick = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) setState(() {});
      });
      setState(() => _bridge = b);
    }
    if (mounted) await showDialog(context: context, builder: (_) => _BridgeDialog(bridge: _bridge!));
  }

  Future<void> _stopBridge() async {
    await _bridge?.stop();
    _tick?.cancel();
    setState(() => _bridge = null);
  }

  void _validateAndNext() {
    final s = _state.current;
    if (s == null) return;
    if (s.photo == null) {
      toast(context, 'Ajoutez d\'abord la photo de ${s.fullName}.', error: true);
      return;
    }
    _state.setValidated(s, true);
    if (_state.validatedCount == _state.students.length) {
      toast(context, 'Toutes les cartes sont validées. Passez à l\'impression.');
      return;
    }
    // Élève suivant non validé
    final n = _state.students.length;
    for (var k = 1; k <= n; k++) {
      final i = (_state.currentIndex + k) % n;
      if (!_state.students[i].validated) {
        _state.goTo(i);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = state.current;
    if (s == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.photo_camera_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            const Text('Ajoutez d\'abord la liste des élèves.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: widget.onGoToStudents, child: const Text('Aller à la liste des élèves')),
          ]),
        ),
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final main = _buildMain(context, state, s, wide);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => state.move(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => state.move(-1),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _validateAndNext,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: wide
            ? Row(children: [
                SizedBox(width: 320, child: _StudentList(state: state)),
                const VerticalDivider(width: 1),
                Expanded(child: main),
              ])
            : main,
      ),
    );
  }

  Widget _buildMain(BuildContext context, AppState state, Student s, bool wide) {
    final scheme = Theme.of(context).colorScheme;
    final bridge = _bridge;
    final connected = bridge?.lastSeen.value != null &&
        DateTime.now().difference(bridge!.lastSeen.value!) < const Duration(seconds: 5);

    final actions = Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
      if (!isDesktop)
        FilledButton.icon(
          onPressed: _working ? null : _takePhoto,
          icon: const Icon(Icons.photo_camera),
          label: const Text('Prendre la photo'),
        ),
      if (isDesktop)
        FilledButton.icon(
          onPressed: _working ? null : _startBridge,
          icon: const Icon(Icons.phonelink_ring),
          label: Text(bridge == null ? 'Caméra du téléphone' : 'Afficher le QR code'),
        ),
      OutlinedButton.icon(
        onPressed: _working ? null : _pickFile,
        icon: const Icon(Icons.photo_library_outlined),
        label: Text(isDesktop ? 'Choisir un fichier' : 'Galerie'),
      ),
      if (s.photo != null)
        TextButton.icon(
          onPressed: () => state.setPhoto(s, null),
          icon: const Icon(Icons.hide_image_outlined),
          label: const Text('Retirer la photo'),
        ),
      TextButton.icon(
        onPressed: () async {
          final e = await editStudent(context, s, classes: state.classes);
          if (e != null) state.upsertStudent(e);
        },
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Modifier les infos'),
      ),
    ]);

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (bridge != null)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: connected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Icon(connected ? Icons.smartphone : Icons.wifi_find, color: scheme.primary),
            Text(
              connected
                  ? 'Téléphone connecté · ${bridge.received.value} photo(s) reçue(s)'
                  : 'En attente du téléphone…',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(value: _autoAdvance, onChanged: (v) => setState(() => _autoAdvance = v ?? true)),
              const Text('Passer à l\'élève suivant après chaque photo'),
            ]),
            TextButton(onPressed: _startBridge, child: const Text('QR code')),
            TextButton(onPressed: _stopBridge, child: const Text('Arrêter')),
          ]),
        ),
      Row(children: [
        IconButton.filledTonal(
          tooltip: 'Précédent (←)',
          onPressed: state.currentIndex > 0 ? () => state.move(-1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Column(children: [
            Text('Élève ${state.currentIndex + 1} sur ${state.students.length}',
                style: Theme.of(context).textTheme.labelLarge),
            Text(s.fullName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            if (!wide)
              TextButton.icon(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => SizedBox(height: 520, child: _StudentList(state: state, closeOnTap: true)),
                ),
                icon: const Icon(Icons.list),
                label: const Text('Liste des élèves'),
              ),
          ]),
        ),
        IconButton.filledTonal(
          tooltip: 'Suivant (→)',
          onPressed: state.currentIndex < state.students.length - 1 ? () => state.move(1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ]),
      const SizedBox(height: 16),
      Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: state.template.landscape ? 620 : 360, maxHeight: 560),
          child: Stack(alignment: Alignment.center, children: [
            FittedBox(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
                ),
                child: CardView(template: state.template, school: state.school, student: s, scale: 6.5),
              ),
            ),
            if (_working) const CircularProgressIndicator(),
            if (s.validated)
              Positioned(
                top: 8,
                right: 8,
                child: Chip(
                  avatar: const Icon(Icons.verified, color: Colors.green, size: 18),
                  label: const Text('Validée'),
                  backgroundColor: scheme.surface,
                ),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      actions,
      const SizedBox(height: 16),
      Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 8, children: [
        if (s.validated)
          OutlinedButton.icon(
            onPressed: () => state.setValidated(s, false),
            icon: const Icon(Icons.undo),
            label: const Text('Annuler la validation'),
          ),
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
          onPressed: _validateAndNext,
          icon: const Icon(Icons.check),
          label: const Text('Valider la carte et passer à la suivante'),
        ),
      ]),
      const SizedBox(height: 12),
      Center(
        child: Text(
          '${state.validatedCount} / ${state.students.length} cartes validées',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      if (state.validatedCount == state.students.length && state.students.isNotEmpty) ...[
        const SizedBox(height: 12),
        Center(
          child: FilledButton.tonalIcon(
            onPressed: widget.onNext,
            icon: const Icon(Icons.print),
            label: const Text('Générer les cartes'),
          ),
        ),
      ],
      if (isDesktop) ...[
        const SizedBox(height: 16),
        Center(
          child: Text('Raccourcis : ← → pour naviguer, Ctrl + Entrée pour valider',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ]);
  }
}

class _StudentList extends StatefulWidget {
  final AppState state;
  final bool closeOnTap;
  const _StudentList({required this.state, this.closeOnTap = false});

  @override
  State<_StudentList> createState() => _StudentListState();
}

class _StudentListState extends State<_StudentList> {
  String _q = '';
  bool _missingOnly = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final q = _q.toLowerCase();
    final items = <int>[
      for (var i = 0; i < state.students.length; i++)
        if ((!_missingOnly || state.students[i].photo == null) &&
            (q.isEmpty || '${state.students[i].fullName} ${state.students[i].classe}'.toLowerCase().contains(q)))
          i,
    ];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher'),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      CheckboxListTile(
        dense: true,
        value: _missingOnly,
        onChanged: (v) => setState(() => _missingOnly = v ?? false),
        title: Text('Sans photo seulement (${state.students.length - state.photoCount})'),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, k) {
            final i = items[k];
            final s = state.students[i];
            return ListTile(
              dense: true,
              selected: i == state.currentIndex,
              leading: CircleAvatar(
                radius: 18,
                backgroundImage: s.photo != null ? MemoryImage(s.photo!) : null,
                child: s.photo == null ? Text(s.initials, style: const TextStyle(fontSize: 12)) : null,
              ),
              title: Text(s.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(s.classe),
              trailing: s.validated
                  ? const Icon(Icons.verified, color: Colors.green, size: 20)
                  : s.photo != null
                      ? const Icon(Icons.image_outlined, size: 20)
                      : const Icon(Icons.radio_button_unchecked, size: 20, color: Colors.black26),
              onTap: () {
                state.goTo(i);
                if (widget.closeOnTap) Navigator.pop(context);
              },
            );
          },
        ),
      ),
    ]);
  }
}

class _BridgeDialog extends StatefulWidget {
  final PhoneBridge bridge;
  const _BridgeDialog({required this.bridge});

  @override
  State<_BridgeDialog> createState() => _BridgeDialogState();
}

class _BridgeDialogState extends State<_BridgeDialog> {
  List<String> _ips = [];
  String? _ip;

  @override
  void initState() {
    super.initState();
    PhoneBridge.localIps().then((l) {
      if (mounted) {
        setState(() {
          _ips = l;
          _ip = l.isEmpty ? null : l.first;
        });
      }
    });
    widget.bridge.lastSeen.addListener(_onSeen);
  }

  void _onSeen() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.bridge.lastSeen.removeListener(_onSeen);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = _ip == null ? null : widget.bridge.urlFor(_ip!);
    final seen = widget.bridge.lastSeen.value != null;
    return AlertDialog(
      title: const Text('Utiliser la caméra du téléphone'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('1. Connectez le téléphone au même Wi-Fi que cet ordinateur (ou au partage de connexion).\n'
                '2. Scannez ce QR code avec l\'appareil photo du téléphone.\n'
                '3. Sur la page qui s\'ouvre, touchez « Prendre la photo » : elle arrive ici sur la carte de l\'élève affiché.'),
            const SizedBox(height: 16),
            if (_ips.isEmpty)
              const Text('Aucun réseau détecté. Connectez l\'ordinateur à un réseau Wi-Fi ou Ethernet.',
                  style: TextStyle(color: Colors.red))
            else ...[
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(data: url!, size: 240, backgroundColor: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(url, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (_ips.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _ip,
                  decoration: const InputDecoration(labelText: 'Adresse réseau (si le téléphone ne se connecte pas)'),
                  items: [for (final i in _ips) DropdownMenuItem(value: i, child: Text(i))],
                  onChanged: (v) => setState(() => _ip = v),
                ),
              ],
            ],
            const SizedBox(height: 12),
            Row(children: [
              Icon(seen ? Icons.check_circle : Icons.hourglass_empty,
                  color: seen ? Colors.green : Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(seen ? 'Le téléphone est connecté.' : 'En attente du téléphone…')),
            ]),
            const SizedBox(height: 8),
            Text(
              'Sous Windows, autorisez l\'application dans le pare-feu (réseaux privés) si une fenêtre le demande.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
    );
  }
}
