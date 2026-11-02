import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_state.dart';
import '../card_kinds.dart';
import '../models.dart';
import '../services/license.dart';
import '../widgets/common.dart';
import 'attendance_controller.dart';
import 'attendance_export.dart';
import 'attendance_models.dart';
import 'sms_service.dart';

/// La caméra n'est utilisable pour le scan que sur téléphone et tablette.
bool get cameraScanSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

const _green = Color(0xFF0B6B3A);
const _orange = Color(0xFFB25E00);
const _red = Color(0xFFC62828);
const _blue = Color(0xFF1B2A6B);

Color statusColor(DayStatus s) => switch (s) {
      DayStatus.present => _green,
      DayStatus.late => _orange,
      DayStatus.absent => _red,
      DayStatus.excused => _blue,
      DayStatus.notYet => Colors.grey,
    };

/// Onglet « Présences » : borne de pointage, journée en cours, rapport Excel, réglages.
class AttendanceScreen extends StatelessWidget {
  final bool active;
  const AttendanceScreen({super.key, required this.active});

  @override
  Widget build(BuildContext context) {
    final ctrl = AttendanceScope.of(context);
    if (!ctrl.loaded) return const Center(child: CircularProgressIndicator());
    return DefaultTabController(
      length: 4,
      child: Column(children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: const TabBar(isScrollable: true, tabAlignment: TabAlignment.center, tabs: [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Pointage'),
            Tab(icon: Icon(Icons.today), text: 'Aujourd\'hui'),
            Tab(icon: Icon(Icons.table_view), text: 'Rapport Excel'),
            Tab(icon: Icon(Icons.tune), text: 'Réglages'),
          ]),
        ),
        Expanded(
          child: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
            _ActiveTab(active: active, child: (on) => ScanStation(cameraActive: on)),
            const TodayView(),
            const ReportView(),
            const AttendanceSettingsView(),
          ]),
        ),
      ]),
    );
  }
}

/// N'allume la caméra que si l'onglet Pointage est réellement affiché.
class _ActiveTab extends StatefulWidget {
  final bool active;
  final Widget Function(bool active) child;
  const _ActiveTab({required this.active, required this.child});

  @override
  State<_ActiveTab> createState() => _ActiveTabState();
}

class _ActiveTabState extends State<_ActiveTab> {
  TabController? _tc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tc?.removeListener(_on);
    _tc = DefaultTabController.maybeOf(context)?..addListener(_on);
  }

  void _on() => setState(() {});

  @override
  void dispose() {
    _tc?.removeListener(_on);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child(widget.active && (_tc?.index ?? 0) == 0);
}

// =====================================================================
// Borne de pointage
// =====================================================================

class ScanStation extends StatefulWidget {
  final bool cameraActive;

  /// Plein écran : écran toujours allumé, interface simplifiée.
  final bool kiosk;
  const ScanStation({super.key, required this.cameraActive, this.kiosk = false});

  @override
  State<ScanStation> createState() => _ScanStationState();
}

class _ScanStationState extends State<ScanStation> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  AudioPlayer? _player;
  MobileScannerController? _cam;
  bool _useCamera = cameraScanSupported;
  bool _frontCamera = false;
  ScanResult? _last;
  Timer? _clear;
  String _lastCode = '';
  DateTime _lastCodeAt = DateTime(2000);
  final List<ScanResult> _recent = [];

  @override
  void initState() {
    super.initState();
    if (widget.kiosk) WakelockPlus.enable().catchError((_) {});
    _syncCamera();
  }

  @override
  void didUpdateWidget(ScanStation old) {
    super.didUpdateWidget(old);
    _syncCamera();
  }

  void _syncCamera() {
    final want = widget.cameraActive && _useCamera && cameraScanSupported;
    if (want && _cam == null) {
      _cam = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.normal,
        facing: _frontCamera ? CameraFacing.front : CameraFacing.back,
      );
    } else if (!want && _cam != null) {
      final c = _cam;
      _cam = null;
      c?.dispose();
    }
  }

  @override
  void dispose() {
    if (widget.kiosk) WakelockPlus.disable().catchError((_) {});
    _cam?.dispose();
    _player?.dispose();
    _clear?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _handle(String code, String source) {
    code = code.trim();
    if (code.isEmpty) return;
    // La caméra voit la même carte plusieurs fois par seconde : on attend qu'elle change.
    final now = DateTime.now();
    if (source == 'camera' && code == _lastCode && now.difference(_lastCodeAt).inSeconds < 4) return;
    _lastCode = code;
    _lastCodeAt = now;
    final r = AttendanceScope.read(context).scan(code, source: source);
    _feedback(r);
    setState(() {
      _last = r;
      if (!r.unknown && !r.duplicate) {
        _recent.insert(0, r);
        if (_recent.length > 30) _recent.removeLast();
      }
    });
    _clear?.cancel();
    _clear = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _last = null);
    });
  }

  Future<void> _feedback(ScanResult r) async {
    try {
      final player = _player ??= AudioPlayer();
      if (r.unknown) {
        HapticFeedback.heavyImpact();
        await player.play(AssetSource('sounds/error.wav'));
      } else if (r.duplicate) {
        HapticFeedback.selectionClick();
      } else {
        HapticFeedback.mediumImpact();
        await player.play(AssetSource(r.entry ? 'sounds/ok.wav' : 'sounds/exit.wav'));
      }
    } catch (_) {}
  }

  void _submitKeyboard(String v) {
    _handle(v, 'douchette');
    _input.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = AttendanceScope.of(context);
    final app = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final sum = ctrl.todaySummary();
    final present = sum.where((d) => d.status == DayStatus.present || d.status == DayStatus.late).length;
    final out = sum.where((d) => d.isOut).length;
    final late = sum.where((d) => d.status == DayStatus.late).length;
    final missing = sum.where((d) => d.status == DayStatus.absent || d.status == DayStatus.notYet).length;

    final modeSel = SegmentedButton<ScanMode>(
      segments: const [
        ButtonSegment(value: ScanMode.auto, label: Text('Auto'), icon: Icon(Icons.sync_alt)),
        ButtonSegment(value: ScanMode.entry, label: Text('Entrée'), icon: Icon(Icons.login)),
        ButtonSegment(value: ScanMode.exit, label: Text('Sortie'), icon: Icon(Icons.logout)),
      ],
      selected: {ctrl.settings.mode},
      onSelectionChanged: (v) {
        ctrl.settings.mode = v.first;
        ctrl.saveSettings();
      },
    );

    final keyboardField = TextField(
      controller: _input,
      focusNode: _focus,
      autofocus: !cameraScanSupported || widget.kiosk,
      textInputAction: TextInputAction.done,
      onSubmitted: _submitKeyboard,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.qr_code_2),
        labelText: 'Douchette ou matricule',
        hintText: 'Scannez la carte (ou tapez le matricule puis Entrée)',
        suffixIcon: IconButton(icon: const Icon(Icons.keyboard_return), onPressed: () => _submitKeyboard(_input.text)),
      ),
    );

    final camera = (_cam != null)
        ? ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(fit: StackFit.expand, children: [
                MobileScanner(
                  controller: _cam,
                  onDetect: (cap) {
                    for (final b in cap.barcodes) {
                      final v = b.rawValue;
                      if (v != null && v.isNotEmpty) {
                        _handle(v, 'camera');
                        break;
                      }
                    }
                  },
                  errorBuilder: (c, e) => Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(16),
                    child: Text(
                        'Caméra indisponible : ${e.errorCode.name}\nAutorisez la caméra dans les réglages du téléphone.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white)),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.62,
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 3),
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: Text('Présentez le QR code de la carte',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, shadows: [
                        Shadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 6),
                      ])),
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: IconButton.filledTonal(
                    tooltip: 'Changer de caméra',
                    icon: const Icon(Icons.cameraswitch),
                    onPressed: () {
                      _frontCamera = !_frontCamera;
                      _cam?.switchCamera();
                    },
                  ),
                ),
              ]),
            ),
          )
        : null;

    final counters = Wrap(spacing: 8, runSpacing: 8, children: [
      _Counter('Présents', present, _green, Icons.how_to_reg),
      _Counter('Retards', late, _orange, Icons.schedule),
      _Counter('Sortis', out, _blue, Icons.logout),
      _Counter(DateTime.now().isBefore(ctrl.settings.absenceLimit(DateTime.now())) ? 'Non arrivés' : 'Absents', missing,
          _red, Icons.person_off),
    ]);

    final result = _ResultCard(result: _last, big: wide || widget.kiosk, company: ctrl.isCompany);

    final recent = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Derniers passages', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      if (_recent.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Aucun passage depuis l\'ouverture de cet écran.'),
        ),
      for (final r in _recent.take(widget.kiosk ? 6 : 12))
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: StudentAvatar(student: r.student!, radius: 18),
          title: Text(r.student!.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(r.student!.classe),
          trailing: Text('${r.entry ? 'Entrée' : 'Sortie'} ${hhmm(r.time)}',
              style: TextStyle(color: r.entry ? _green : _blue, fontWeight: FontWeight.w700)),
        ),
    ]);

    final controls = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!app.template.showQr) const QrWarning(),
      if (!ctrl.isSchoolDay)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _Banner(
            color: _orange,
            icon: Icons.event_busy,
            text: ctrl.today.closed
                ? 'Aujourd\'hui est marqué « jour sans école » : aucun SMS d\'absence ne sera envoyé.'
                : 'Aujourd\'hui n\'est pas un jour ouvré dans les réglages : aucun SMS d\'absence ne sera envoyé.',
          ),
        ),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: modeSel),
      const SizedBox(height: 12),
      keyboardField,
      if (cameraScanSupported) ...[
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Scanner avec la caméra'),
          value: _useCamera,
          onChanged: (v) => setState(() {
            _useCamera = v;
            _syncCamera();
          }),
        ),
      ],
      if (!widget.kiosk)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: FilledButton.icon(
            icon: const Icon(Icons.fullscreen),
            label: const Text('Mode borne plein écran'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KioskPage())),
          ),
        ),
    ]);

    if (wide) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 380,
            child: ListView(children: [
              controls,
              if (camera != null) ...[const SizedBox(height: 12), camera],
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ListView(children: [
              result,
              const SizedBox(height: 12),
              counters,
              const SizedBox(height: 16),
              recent,
            ]),
          ),
        ]),
      );
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      controls,
      const SizedBox(height: 12),
      if (camera != null) ...[
        Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420), child: camera)),
        const SizedBox(height: 12),
      ],
      result,
      const SizedBox(height: 12),
      counters,
      const SizedBox(height: 16),
      recent,
    ]);
  }
}

/// Borne en plein écran : l'écran reste allumé.
class KioskPage extends StatelessWidget {
  const KioskPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: Text(app.school.name.isEmpty ? 'Borne de pointage' : app.school.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('${frWeekdays[now.weekday - 1]} ${frDate(now)}')),
          ),
        ],
      ),
      body: const ScanStation(cameraActive: true, kiosk: true),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ScanResult? result;
  final bool big;
  final bool company;
  const _ResultCard({required this.result, required this.big, this.company = false});

  @override
  Widget build(BuildContext context) {
    final r = result;
    final t = Theme.of(context).textTheme;
    if (r == null) {
      return Container(
        height: big ? 220 : 130,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 2),
        ),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.badge_outlined, size: big ? 64 : 40, color: Colors.grey),
          const SizedBox(height: 8),
          Text('En attente d\'une carte…', style: t.titleMedium?.copyWith(color: Colors.grey)),
        ]),
      );
    }
    if (r.unknown) {
      return _box(context, _red, Icons.error_outline, 'Carte inconnue',
          'Ce code ne correspond à aucune fiche de ce projet.\nCode lu : ${r.code.length > 40 ? '${r.code.substring(0, 40)}…' : r.code}');
    }
    final s = r.student!;
    final color = r.duplicate ? Colors.grey.shade700 : (r.entry ? (r.late ? _orange : _green) : _blue);
    final label = r.duplicate
        ? 'Déjà pointé à ${hhmm(r.time)}'
        : r.entry
            ? (r.late ? 'ENTRÉE ${hhmm(r.time)} · EN RETARD' : 'ENTRÉE ${hhmm(r.time)}')
            : company
                ? 'SORTIE ${hhmm(r.time)} · ${hoursLabel(r.workedMin)} AUJOURD\'HUI'
                : 'SORTIE ${hhmm(r.time)}';
    return Container(
      padding: EdgeInsets.all(big ? 20 : 14),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        StudentAvatar(student: s, radius: big ? 70 : 42, square: true),
        SizedBox(width: big ? 20 : 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.fullName,
                style: (big ? t.headlineMedium : t.titleLarge)
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            Text('${s.classe}${s.matricule.isNotEmpty ? ' · ${s.matricule}' : ''}',
                style: (big ? t.titleLarge : t.titleMedium)?.copyWith(color: Colors.white70)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration:
                  BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(30)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(r.duplicate ? Icons.replay : (r.entry ? Icons.login : Icons.logout), color: Colors.white),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      style: (big ? t.titleLarge : t.titleMedium)
                          ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _box(BuildContext context, Color c, IconData i, String title, String sub) => Container(
        padding: EdgeInsets.all(big ? 24 : 16),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(i, color: Colors.white, size: big ? 72 : 44),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
              Text(sub, style: const TextStyle(color: Colors.white)),
            ]),
          ),
        ]),
      );
}

class _Counter extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  const _Counter(this.label, this.value, this.color, this.icon);

  @override
  Widget build(BuildContext context) => Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$value',
                  style:
                      Theme.of(context).textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
              Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      );
}

class StudentAvatar extends StatelessWidget {
  final Student student;
  final double radius;
  final bool square;
  const StudentAvatar({super.key, required this.student, this.radius = 20, this.square = false});

  @override
  Widget build(BuildContext context) {
    final p = student.photo;
    if (square) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius * 0.18),
        child: Container(
          width: radius * 1.5,
          height: radius * 2,
          color: Colors.white24,
          alignment: Alignment.center,
          child: p != null
              ? Image.memory(p, fit: BoxFit.cover, width: radius * 1.5, height: radius * 2, gaplessPlayback: true)
              : Text(student.initials,
                  style: TextStyle(color: Colors.white, fontSize: radius * 0.6, fontWeight: FontWeight.w800)),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundImage: p != null ? MemoryImage(p) : null,
      child: p == null ? Text(student.initials, style: TextStyle(fontSize: radius * 0.7)) : null,
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  final Widget? action;
  const _Banner({required this.color, required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ]),
      );
}

/// Avertit si les cartes imprimées n'ont pas de QR code.
class QrWarning extends StatelessWidget {
  const QrWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _Banner(
        color: _red,
        icon: Icons.qr_code,
        text: 'Le QR code n\'est pas activé sur le modèle de carte. Activez-le puis réimprimez les cartes '
            'pour pouvoir les scanner (sinon, tapez le matricule).',
        action: FilledButton(
          onPressed: () {
            app.template.showQr = true;
            app.changed();
            toast(context, 'QR code activé sur le modèle. Réimprimez les cartes depuis l\'onglet Impression.');
          },
          child: const Text('Activer'),
        ),
      ),
    );
  }
}

// =====================================================================
// Journée en cours
// =====================================================================

enum _Filter { all, present, late, absent, out, excused }

class TodayView extends StatefulWidget {
  const TodayView({super.key});

  @override
  State<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<TodayView> {
  _Filter _filter = _Filter.all;
  String _query = '';
  String _classe = '';

  bool _match(StudentDay d) => switch (_filter) {
        _Filter.all => true,
        _Filter.present => d.status == DayStatus.present || d.status == DayStatus.late,
        _Filter.late => d.status == DayStatus.late,
        _Filter.absent => d.status == DayStatus.absent || d.status == DayStatus.notYet,
        _Filter.out => d.isOut,
        _Filter.excused => d.status == DayStatus.excused,
      };

  Future<void> _sendAll(AttendanceController ctrl, bool licensed) async {
    if (!licensed) {
      toast(context, 'L\'envoi de SMS nécessite une licence active.', error: true);
      return;
    }
    final pending = ctrl.pendingAbsences();
    if (pending.isEmpty) {
      toast(context, 'Aucun SMS à envoyer : pas d\'absent sans message.');
      return;
    }
    if (!await SmsService.requestPermission()) {
      if (mounted) toast(context, 'Autorisez l\'envoi de SMS pour l\'application.', error: true);
      return;
    }
    if (!mounted) return;
    if (!await confirm(context, 'Envoyer les SMS d\'absence',
        '${pending.length} destinataire(s) vont recevoir un SMS depuis la puce de ce téléphone (coût d\'un SMS normal).',
        ok: 'Envoyer')) {
      return;
    }
    final (ok, ko, none) = await ctrl.sendAbsenceSms();
    if (mounted) {
      toast(context, '$ok SMS envoyé(s)${ko > 0 ? ', $ko échec(s)' : ''}${none > 0 ? ', $none sans numéro' : ''}.',
          error: ko > 0);
    }
  }

  Future<void> _sendOne(AttendanceController ctrl, Student s, bool licensed) async {
    final to = normalizePhone(s.contact, ctrl.settings.countryCode);
    if (to == null) {
      toast(context, 'Pas de numéro valide pour ${s.fullName}.', error: true);
      return;
    }
    if (!SmsService.supported) {
      await SmsService.openWhatsApp(to, ctrl.messageFor(s));
      return;
    }
    if (!licensed) {
      toast(context, 'L\'envoi de SMS nécessite une licence active.', error: true);
      return;
    }
    if (!await SmsService.requestPermission()) {
      if (mounted) toast(context, 'Autorisez l\'envoi de SMS pour l\'application.', error: true);
      return;
    }
    final (ok, _, _) = await ctrl.sendAbsenceSms(only: [s]);
    if (mounted) toast(context, ok == 1 ? 'SMS envoyé.' : 'Échec : ${ctrl.today.sms[s.id] ?? ''}', error: ok != 1);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = AttendanceScope.of(context);
    final licensed = !LicenseScope.trialOf(context);
    final kind = kindById(AppScope.of(context).template.kind);
    final company = ctrl.isCompany;
    final who = company ? 'employé(s)' : '${kind.person}(s)';
    final all = ctrl.todaySummary();
    final classes = {for (final d in all) d.student.classe.trim()}.where((c) => c.isNotEmpty).toList()..sort();
    final q = _query.toLowerCase();
    final list = all
        .where((d) => _classe.isEmpty || d.student.classe.trim() == _classe)
        .where((d) => q.isEmpty || '${d.student.fullName} ${d.student.matricule}'.toLowerCase().contains(q))
        .where(_match)
        .toList()
      ..sort((a, b) {
        final c = a.student.classe.compareTo(b.student.classe);
        return c != 0 ? c : a.student.fullName.compareTo(b.student.fullName);
      });
    int count(_Filter f) {
      final old = _filter;
      _filter = f;
      final n = all.where((d) => _classe.isEmpty || d.student.classe.trim() == _classe).where(_match).length;
      _filter = old;
      return n;
    }

    final pending = ctrl.pendingAbsences().length;
    final now = DateTime.now();
    final afterCutoff = now.isAfter(ctrl.settings.absenceLimit(now));

    return ListView(padding: const EdgeInsets.all(12), children: [
      Section(
        title: '${frWeekdays[now.weekday - 1]} ${frDate(now)}',
        subtitle: afterCutoff
            ? 'Après ${ctrl.settings.absenceTime}, les $who non pointés sont absents.'
            : 'Les $who non pointés seront déclarés absents à ${ctrl.settings.absenceTime}.',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Jour sans école'),
          Switch(value: ctrl.today.closed, onChanged: ctrl.setClosed),
        ]),
        children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Icon(Icons.sms_outlined, color: Theme.of(context).colorScheme.primary),
            Text(pending == 0
                ? 'Aucun SMS d\'absence en attente.'
                : '$pending absent(s) sans SMS envoyé.${ctrl.autoSmsOn && SmsService.supported ? ' Envoi automatique à ${ctrl.settings.absenceTime}.' : ''}'),
            if (SmsService.supported)
              FilledButton.icon(
                onPressed: ctrl.sending || pending == 0 ? null : () => _sendAll(ctrl, licensed),
                icon: ctrl.sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(ctrl.sending ? 'Envoi en cours…' : 'Envoyer les SMS maintenant'),
              )
            else
              const Text('Sur ordinateur : ouvrez le menu à droite d\'un absent pour prévenir par WhatsApp.',
                  style: TextStyle(fontStyle: FontStyle.italic)),
          ]),
          if (ctrl.lastSendReport != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('Dernier envoi : ${ctrl.lastSendReport}')),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 260,
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher'),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        if (classes.isNotEmpty)
          DropdownButton<String>(
            value: _classe,
            items: [
              DropdownMenuItem(value: '', child: Text('Tous : ${kind.group.toLowerCase()}')),
              for (final c in classes) DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _classe = v ?? ''),
          ),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (f, l) in [
          (_Filter.all, 'Tous'),
          (_Filter.present, 'Présents'),
          (_Filter.late, 'Retards'),
          (_Filter.absent, afterCutoff ? 'Absents' : 'Pas encore arrivés'),
          (_Filter.out, 'Sortis'),
          (_Filter.excused, 'Justifiés'),
        ])
          ChoiceChip(
              label: Text('$l (${count(f)})'), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
      ]),
      const SizedBox(height: 8),
      if (list.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Personne dans cette liste.'))),
      for (final d in list)
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            leading: StudentAvatar(student: d.student),
            title: Text(d.student.fullName),
            subtitle: Text([
              d.student.classe,
              if (d.arrival != null) 'Arrivée ${hhmm(d.arrival!)}',
              if (d.departure != null) 'Sortie ${hhmm(d.departure!)}',
              if (company && d.workedMin > 0) '${hoursLabel(d.workedMin)} travaillées',
              if (d.sms != null) 'SMS : ${d.sms}',
            ].join(' · ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Chip(
                label: Text(d.isOut ? 'Sorti' : dayStatusLabel[d.status]!,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                backgroundColor: d.isOut ? _blue : statusColor(d.status),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'present':
                      ctrl.setOverride(d.student, DayOverride.present);
                    case 'excused':
                      ctrl.setOverride(d.student, DayOverride.excused);
                    case 'absent':
                      ctrl.setOverride(d.student, DayOverride.absent);
                    case 'reset':
                      ctrl.setOverride(d.student, null);
                    case 'undo':
                      ctrl.undoLast(d.student);
                    case 'sms':
                      _sendOne(ctrl, d.student, licensed);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'present', child: Text('Marquer présent')),
                  const PopupMenuItem(value: 'excused', child: Text('Absence justifiée')),
                  const PopupMenuItem(value: 'absent', child: Text('Marquer absent')),
                  if (ctrl.today.overrides.containsKey(d.student.id))
                    const PopupMenuItem(value: 'reset', child: Text('Annuler la correction')),
                  if (d.scans > 0) const PopupMenuItem(value: 'undo', child: Text('Annuler le dernier passage')),
                  if (d.status == DayStatus.absent || d.status == DayStatus.notYet)
                    PopupMenuItem(
                        value: 'sms', child: Text(SmsService.supported ? 'Envoyer le SMS' : 'Prévenir par WhatsApp')),
                ],
              ),
            ]),
          ),
        ),
    ]);
  }
}

// =====================================================================
// Rapport Excel
// =====================================================================

class ReportView extends StatefulWidget {
  const ReportView({super.key});

  @override
  State<ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<ReportView> {
  late DateTimeRange _range = _month();
  String _preset = 'month';
  String _classe = '';
  bool _busy = false;

  static DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);
  static DateTimeRange _month() {
    final n = DateTime.now();
    return DateTimeRange(start: DateTime(n.year, n.month, 1), end: _d(n));
  }

  void _setPreset(String p) {
    final n = _d(DateTime.now());
    setState(() {
      _preset = p;
      _range = switch (p) {
        'today' => DateTimeRange(start: n, end: n),
        'week' => DateTimeRange(start: n.subtract(Duration(days: n.weekday - 1)), end: n),
        'lastmonth' => DateTimeRange(start: DateTime(n.year, n.month - 1, 1), end: DateTime(n.year, n.month, 0)),
        _ => _month(),
      };
    });
  }

  Future<void> _custom() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
      helpText: 'Choisir la période',
    ).catchError((_) => null);
    if (r != null) {
      setState(() {
        _range = r;
        _preset = 'custom';
      });
    }
  }

  Future<void> _export() async {
    final ctrl = AttendanceScope.read(context);
    final app = AppScope.read(context);
    final trial = LicenseScope.trialOf(context);
    setState(() => _busy = true);
    try {
      await ctrl.flush();
      final days = await ctrl.daysBetween(_range.start, _range.end);
      final bytes = buildAttendanceExcel(
        students: app.students,
        days: days,
        settings: ctrl.settings,
        school: app.school,
        from: _range.start,
        to: _range.end,
        classFilter: _classe,
        trial: trial,
        company: ctrl.isCompany,
        groupLabel: kindById(app.template.kind).group,
      );
      String two(int v) => v.toString().padLeft(2, '0');
      final name =
          '${ctrl.isCompany ? 'heures' : 'presences'}_${dateKey(_range.start)}_au_${dateKey(_range.end)}${_classe.isEmpty ? '' : '_${_classe.replaceAll(RegExp(r'[^\w]'), '')}'}.xlsx';
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Enregistrer le rapport de présences',
        fileName: name,
        bytes: bytes,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (uri != null && mounted) {
        toast(context,
            'Rapport Excel enregistré (${days.length} jour(s), édité à ${two(DateTime.now().hour)}h${two(DateTime.now().minute)}).');
      }
    } catch (e) {
      if (mounted) toast(context, 'Export impossible : $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final kind = kindById(app.template.kind);
    final company = AttendanceScope.of(context).isCompany;
    final classes = {for (final s in app.students) s.classe.trim()}.where((c) => c.isNotEmpty).toList()..sort();
    if (!classes.contains(_classe)) _classe = '';
    return ListView(padding: const EdgeInsets.all(12), children: [
      Section(
        title: 'Rapport de présences',
        subtitle: company
            ? 'Fichier Excel : heures travaillées, retards, heures sup. et départs anticipés par employé, détail par jour, tous les passages.'
            : 'Fichier Excel avec 3 feuilles : Synthèse par personne, Présences par jour, Tous les passages.',
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, l) in [
              ('today', 'Aujourd\'hui'),
              ('week', 'Cette semaine'),
              ('month', 'Ce mois'),
              ('lastmonth', 'Mois dernier'),
            ])
              ChoiceChip(label: Text(l), selected: _preset == k, onSelected: (_) => _setPreset(k)),
            ChoiceChip(
                label: const Text('Autre période…'), selected: _preset == 'custom', onSelected: (_) => _custom()),
          ]),
          const SizedBox(height: 12),
          Text('Du ${frDate(_range.start)} au ${frDate(_range.end)}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(children: [
            Text('${kind.group} : '),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _classe,
              items: [
                const DropdownMenuItem(value: '', child: Text('Tous')),
                for (final c in classes) DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _classe = v ?? ''),
            ),
          ]),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: const Text('Exporter en Excel'),
          ),
          if (LicenseScope.trialOf(context))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Version d\'essai : le rapport porte la mention « VERSION D\'ESSAI ».',
                  style: TextStyle(color: _red)),
            ),
          const SizedBox(height: 8),
          const Text(
              'Seuls les jours où des cartes ont été scannées (et non marqués « jour sans école / fermé ») sont comptés.',
              style: TextStyle(fontStyle: FontStyle.italic)),
        ],
      ),
    ]);
  }
}

// =====================================================================
// Réglages
// =====================================================================

class AttendanceSettingsView extends StatefulWidget {
  const AttendanceSettingsView({super.key});

  @override
  State<AttendanceSettingsView> createState() => _AttendanceSettingsViewState();
}

class _AttendanceSettingsViewState extends State<AttendanceSettingsView> {
  bool? _permission;

  @override
  void initState() {
    super.initState();
    SmsService.hasPermission().then((v) {
      if (mounted) setState(() => _permission = v);
    });
  }

  Future<void> _testSms(AttendanceController ctrl) async {
    final c = TextEditingController();
    final app = AppScope.read(context);
    final number = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('SMS de test'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Numéro (ex. 70 00 00 00)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Envoyer')),
        ],
      ),
    );
    if (number == null || !mounted) return;
    final to = normalizePhone(number, ctrl.settings.countryCode);
    if (to == null) {
      toast(context, 'Numéro invalide.', error: true);
      return;
    }
    final sample =
        app.students.isNotEmpty ? app.students.first : (Student(nom: 'OUEDRAOGO', prenom: 'Awa', classe: '6e A'));
    final text =
        '[TEST] ${buildSms(ctrl.smsTemplate, sample, app.school, DateTime.now(), withoutAccents: ctrl.settings.smsWithoutAccents)}';
    if (!SmsService.supported) {
      await SmsService.openWhatsApp(to, text);
      return;
    }
    if (!await SmsService.requestPermission()) {
      if (mounted) toast(context, 'Autorisation SMS refusée.', error: true);
      return;
    }
    try {
      await SmsService.send(to, text);
      if (mounted) toast(context, 'SMS de test envoyé à $to.');
    } catch (e) {
      if (mounted) toast(context, 'Échec : $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = AttendanceScope.of(context);
    final app = AppScope.of(context);
    final s = ctrl.settings;
    final licensed = !LicenseScope.trialOf(context);
    final sample =
        app.students.isNotEmpty ? app.students.first : Student(nom: 'OUEDRAOGO', prenom: 'Awa', classe: '6e A');
    final preview = buildSms(ctrl.smsTemplate, sample, app.school, DateTime.now(), withoutAccents: s.smsWithoutAccents);
    final segs = smsSegments(preview);
    void save() => ctrl.saveSettings();

    Widget time(String label, String value, ValueChanged<String> on) => SizedBox(
          width: 170,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.schedule),
            label: Text('$label : $value'),
            onPressed: () async {
              final (h, m) = AttendanceSettings.parseTime(value);
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: h, minute: m),
                builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
                  child: child!,
                ),
              );
              if (t != null) {
                on('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                save();
              }
            },
          ),
        );

    final company = ctrl.isCompany;
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (!app.template.showQr) const QrWarning(),
      Section(
        title: 'Type de structure',
        subtitle: company
            ? 'Entreprise : heures de travail des employés (arrivée, départ, heures travaillées, heures sup.).'
            : 'École : présences et absences des élèves, SMS aux parents.',
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('École'), icon: Icon(Icons.school_outlined)),
              ButtonSegment(value: true, label: Text('Entreprise'), icon: Icon(Icons.business_center_outlined)),
            ],
            selected: {company},
            onSelectionChanged: (v) {
              s.company = v.first;
              save();
            },
          ),
        ],
      ),
      const SizedBox(height: 12),
      Section(
          title: 'Horaires',
          subtitle: company
              ? 'Utilisés pour les retards, les départs anticipés et les heures prévues.'
              : 'Utilisés pour les retards et les absences.',
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              time(company ? 'Début du travail' : 'Début des cours', s.startTime, (v) => s.startTime = v),
              if (company) time('Fin du travail', s.endTime, (v) => s.endTime = v),
              time('Heure des absences', s.absenceTime, (v) => s.absenceTime = v),
            ]),
            if (company) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Expanded(child: Text('Pause déduite si l\'employé ne pointe pas à midi')),
                DropdownButton<int>(
                  value: [0, 30, 45, 60, 90, 120].contains(s.breakMin) ? s.breakMin : 60,
                  items: [
                    for (final m in [0, 30, 45, 60, 90, 120])
                      DropdownMenuItem(value: m, child: Text(m == 0 ? 'Aucune' : '$m min')),
                  ],
                  onChanged: (v) {
                    s.breakMin = v ?? 60;
                    save();
                  },
                ),
              ]),
              Text('Journée prévue : ${hoursLabel(s.expectedMinutes)}', style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Text('Tolérance avant retard')),
              DropdownButton<int>(
                value: [0, 5, 10, 15, 20, 30].contains(s.lateToleranceMin) ? s.lateToleranceMin : 10,
                items: [
                  for (final m in [0, 5, 10, 15, 20, 30]) DropdownMenuItem(value: m, child: Text('$m min'))
                ],
                onChanged: (v) {
                  s.lateToleranceMin = v ?? 10;
                  save();
                },
              ),
            ]),
            Row(children: [
              const Expanded(child: Text('Ignorer une 2e lecture de la même carte pendant')),
              DropdownButton<int>(
                value: [10, 30, 60, 120, 300].contains(s.doubleScanSeconds) ? s.doubleScanSeconds : 60,
                items: [
                  for (final m in [10, 30, 60, 120, 300])
                    DropdownMenuItem(value: m, child: Text(m < 60 ? '$m s' : '${m ~/ 60} min')),
                ],
                onChanged: (v) {
                  s.doubleScanSeconds = v ?? 60;
                  save();
                },
              ),
            ]),
            const SizedBox(height: 8),
            Text(company ? 'Jours ouvrés' : 'Jours de classe'),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(frWeekdays[d - 1].substring(0, 3)),
                  selected: s.schoolDays.contains(d),
                  onSelected: (v) {
                    v ? s.schoolDays.add(d) : s.schoolDays.remove(d);
                    save();
                  },
                ),
            ]),
          ]),
      const SizedBox(height: 12),
      Section(
        title: company ? 'SMS aux employés non pointés' : 'SMS d\'absence aux parents',
        subtitle: company
            ? 'Envoyé au téléphone de l\'employé qui n\'a pas pointé, par la puce du téléphone.'
            : 'Envoyé au numéro « Personne à prévenir » de chaque élève absent, par la puce du téléphone.',
        children: [
          if (!SmsService.supported)
            const _Banner(
              color: _orange,
              icon: Icons.phone_android,
              text:
                  'L\'envoi automatique de SMS fonctionne uniquement sur un téléphone ou une tablette Android avec une puce. '
                  'Sur ordinateur, vous pouvez prévenir les parents par WhatsApp depuis l\'onglet « Aujourd\'hui ».',
            ),
          if (!licensed)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: _Banner(
                color: _red,
                icon: Icons.lock_outline,
                text: 'Version d\'essai : l\'envoi de SMS est réservé aux licences actives.',
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Envoi automatique'),
            subtitle: Text('À ${s.absenceTime}, si au moins une carte a été scannée dans la journée. '
                'L\'application doit rester ouverte sur la borne.'),
            value: company ? s.companySms : s.autoSms,
            onChanged: (v) {
              if (company) {
                s.companySms = v;
              } else {
                s.autoSms = v;
              }
              save();
            },
          ),
          if (SmsService.supported)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_permission == true ? Icons.check_circle : Icons.warning_amber,
                  color: _permission == true ? _green : _orange),
              title: Text(_permission == true ? 'Autorisation SMS accordée' : 'Autorisation SMS à accorder'),
              trailing: _permission == true
                  ? null
                  : FilledButton(
                      onPressed: () async {
                        final ok = await SmsService.requestPermission();
                        if (mounted) setState(() => _permission = ok);
                      },
                      child: const Text('Autoriser'),
                    ),
            ),
          const SizedBox(height: 8),
          TextSetting(
            label: 'Message',
            value: ctrl.smsTemplate,
            onChanged: (v) {
              s.smsTemplate = v.trim().isEmpty ? AttendanceSettings.defaultTemplate : v;
              save();
            },
          ),
          const SizedBox(height: 6),
          const Text('Variables : {prenom} {nom} {classe} {matricule} {date} {ecole}',
              style: TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Aperçu', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(preview),
              const SizedBox(height: 4),
              Text('${preview.length} caractères · $segs SMS par destinataire',
                  style: TextStyle(color: segs > 1 ? _orange : null, fontWeight: FontWeight.w600)),
            ]),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enlever les accents'),
            subtitle: const Text(
                'Certains accents (ê, ô, ç, ï…) font passer un SMS de 160 à 70 caractères. Les enlever réduit le coût.'),
            value: s.smsWithoutAccents,
            onChanged: (v) {
              s.smsWithoutAccents = v;
              save();
            },
          ),
          Row(children: [
            const Expanded(child: Text('Indicatif ajouté aux numéros à 8 chiffres')),
            SizedBox(
              width: 90,
              child: TextSetting(
                label: '+',
                value: s.countryCode,
                keyboard: TextInputType.number,
                onChanged: (v) {
                  s.countryCode = v.replaceAll(RegExp(r'\D'), '');
                  save();
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.outgoing_mail),
            label: Text(SmsService.supported ? 'Envoyer un SMS de test' : 'Tester par WhatsApp'),
            onPressed: !licensed && SmsService.supported ? null : () => _testSms(ctrl),
          ),
        ],
      ),
    ]);
  }
}
