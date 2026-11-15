import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../main.dart' show isDesktop;
import '../services/license.dart';
import '../widgets/common.dart';
import 'pairing.dart';
import 'sync_controller.dart';

String _ago(DateTime? d) {
  if (d == null) return 'jamais';
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return 'à l\'instant';
  if (m < 60) return 'il y a $m min';
  final h = m ~/ 60;
  if (h < 24) return 'il y a $h h';
  return 'le ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// Encadré « Multi-appareil » de la liste des projets.
class SyncCard extends StatelessWidget {
  const SyncCard({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = SyncScope.maybeOf(context);
    if (sync == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final String text;
    if (!sync.allowed) {
      text = 'Option : travaillez sur l\'ordinateur et le téléphone avec les mêmes données.';
    } else if (!sync.connected) {
      text = 'Option active : touchez pour relier cet appareil.';
    } else if (sync.running) {
      text = 'Synchronisation… ${sync.total == 0 ? '' : '${sync.done}/${sync.total}'}';
    } else {
      text = sync.lastError != null ? 'Erreur : touchez pour voir' : 'Synchronisé ${_ago(sync.lastSync)}';
    }
    return Material(
      color: scheme.secondaryContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        leading: sync.running
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Icon(sync.connected ? Icons.cloud_done_outlined : Icons.devices_outlined),
        title: const Text('Multi-appareil', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(text),
        trailing: sync.connected && sync.allowed
            ? IconButton(
                tooltip: 'Synchroniser maintenant',
                icon: const Icon(Icons.sync),
                onPressed: sync.running ? null : () => runSync(context, sync),
              )
            : const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncScreen())),
      ),
    );
  }
}

Future<void> runSync(BuildContext context, SyncController sync) async {
  final r = await sync.syncNow();
  if (!context.mounted) return;
  if (r == null) {
    if (sync.lastError != null) toast(context, sync.lastError!, error: true);
    return;
  }
  final up = r.uploaded.length + r.deletedRemote.length, down = r.downloaded.length + r.deletedLocal.length;
  toast(
    context,
    r.nothing
        ? 'Tout est déjà à jour.'
        : 'Synchronisé : $up fichier(s) envoyé(s), $down reçu(s).${r.errors.isEmpty ? '' : ' ${r.errors.length} en erreur.'}',
    error: r.errors.isNotEmpty,
  );
}

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _code = TextEditingController();
  String? _msg;

  Future<void> _after(SyncController s, String? m) async {
    if (!mounted) return;
    setState(() => _msg = m);
    if (m == null) await runSync(context, s);
  }

  Future<void> _scan(SyncController s) async {
    final v = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _PairScanPage()));
    if (v == null) return;
    _code.text = normalizePairingCode(v) ?? v;
    await _after(s, await s.join(v));
  }

  Future<void> _showPairing(SyncController s) async {
    final (code, err) = await s.newPairing();
    if (!mounted) return;
    if (code == null) {
      toast(context, err ?? 'Impossible de créer le code.', error: true);
      return;
    }
    await showDialog(context: context, builder: (_) => _PairDialog(code: code));
  }

  @override
  Widget build(BuildContext context) {
    final s = SyncScope.maybeOf(context)!;
    final lm = LicenseScope.of(context);
    final theme = Theme.of(context);
    final phone = !isDesktop;

    final children = <Widget>[];
    if (!s.allowed) {
      children.addAll([
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline),
          title: const Text('Option payante non activée sur cet appareil'),
          subtitle: Text('Demandez l\'option « Multi-appareil » au vendeur pour chaque appareil (ordinateur, '
              'téléphone) en donnant l\'identifiant ci-dessous. La licence se met à jour toute seule.'
              '${lm.isLicensed ? '' : ' Il faut d\'abord une licence active.'}'),
        ),
        SelectableText('Identifiant de cet appareil : ${lm.deviceId}',
            style: theme.textTheme.titleSmall?.copyWith(fontFamily: 'monospace')),
      ]);
    } else if (s.connected) {
      children.addAll([
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud_done_outlined, size: 32),
          title: const Text('Cet appareil est relié au compte'),
          subtitle: Text('Dernière synchronisation : ${_ago(s.lastSync)}'),
        ),
        if (s.running) ...[
          LinearProgressIndicator(value: s.total == 0 ? null : s.done / s.total),
          const SizedBox(height: 6),
          Text('Synchronisation… ${s.done}/${s.total}'),
        ],
        if (s.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(s.lastError!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        if (s.lastReport != null && s.lastError == null)
          Text(
            'Dernier passage : ${s.lastReport!.uploaded.length} envoyé(s), ${s.lastReport!.downloaded.length} reçu(s).',
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: s.running ? null : () => runSync(context, s),
            icon: const Icon(Icons.sync),
            label: const Text('Synchroniser maintenant'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => _showPairing(s),
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Ajouter un autre appareil'),
          ),
          OutlinedButton.icon(
            onPressed: s.running
                ? null
                : () async {
                    if (await confirm(context, 'Délier cet appareil ?',
                        'Les données restent sur l\'appareil, mais ne seront plus synchronisées. '
                            'Pour le relier à nouveau, il faudra un code affiché par un autre appareil du compte.',
                        ok: 'Délier')) {
                      await s.disconnect();
                    }
                  },
            icon: const Icon(Icons.link_off),
            label: const Text('Délier'),
          ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: s.auto,
          title: const Text('Synchroniser automatiquement'),
          subtitle: const Text('Au démarrage puis toutes les 10 minutes, quand vous ne saisissez rien.'),
          onChanged: s.setAuto,
        ),
      ]);
    } else {
      children.addAll([
        Text('Premier appareil', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Si c\'est le premier appareil de l\'établissement à utiliser l\'option : '
            'le compte est créé automatiquement, rien à remplir.'),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: s.busy ? null : () async => _after(s, await s.activate()),
          icon: s.busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_upload_outlined),
          label: const Text('Activer sur cet appareil'),
        ),
        const Divider(height: 32),
        Text('Rejoindre un appareil déjà activé', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Sur l\'appareil déjà relié : Multi-appareil > Ajouter un autre appareil. '
            'Puis scannez le QR code affiché ou tapez le code.'),
        const SizedBox(height: 8),
        if (phone) ...[
          FilledButton.tonalIcon(
            onPressed: s.busy ? null : () => _scan(s),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scanner le QR code'),
          ),
          const SizedBox(height: 8),
        ],
        Row(children: [
          Expanded(
            child: TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Code', hintText: 'ABCD-EFG-HJK'),
              onSubmitted: (_) async => _after(s, await s.join(_code.text)),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: s.busy ? null : () async => _after(s, await s.join(_code.text)),
            child: const Text('Rejoindre'),
          ),
        ]),
      ]);
    }
    if (_msg != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(_msg!, style: TextStyle(color: theme.colorScheme.error)),
      ));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Multi-appareil')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Section(
          title: 'Les mêmes données sur l\'ordinateur et le téléphone',
          subtitle: 'Projets, fiches, photos, notes, bulletins et présences sont synchronisés entre les appareils '
              'du compte. Chaque appareil garde sa propre licence.',
          children: children,
        ),
      ]),
    );
  }
}

/// Code et QR code à montrer au nouvel appareil (valable 15 minutes).
class _PairDialog extends StatefulWidget {
  final String code;
  const _PairDialog({required this.code});

  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  late final DateTime _end = DateTime.now().add(const Duration(minutes: 15));
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _end.difference(DateTime.now());
    final expired = left.isNegative;
    final mm = left.inMinutes.toString().padLeft(2, '0');
    final ss = (left.inSeconds % 60).toString().padLeft(2, '0');
    return AlertDialog(
      title: const Text('Ajouter un appareil'),
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Sur l\'autre appareil : Projets > Multi-appareil > Rejoindre. '
              'Scannez ce QR code avec le téléphone, ou tapez le code.'),
          const SizedBox(height: 12),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(10),
            child: QrImageView(data: pairingQr(widget.code), size: 200, padding: EdgeInsets.zero),
          ),
          const SizedBox(height: 12),
          SelectableText(widget.code,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 2, fontFamily: 'monospace')),
          const SizedBox(height: 6),
          Text(expired ? 'Code expiré : fermez et recommencez.' : 'Valable encore $mm:$ss · une seule utilisation',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
    );
  }
}

class _PairScanPage extends StatefulWidget {
  const _PairScanPage();

  @override
  State<_PairScanPage> createState() => _PairScanPageState();
}

class _PairScanPageState extends State<_PairScanPage> {
  final _cam = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _cam.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scanner le code de l\'autre appareil')),
        body: MobileScanner(
          controller: _cam,
          onDetect: (cap) {
            for (final b in cap.barcodes) {
              final v = b.rawValue;
              if (!_done && v != null && normalizePairingCode(v) != null) {
                _done = true;
                Navigator.pop(context, v);
                break;
              }
            }
          },
          errorBuilder: (c, e) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Caméra indisponible : autorisez la caméra, ou tapez le code.\n${e.errorCode.name}',
                  textAlign: TextAlign.center),
            ),
          ),
        ),
      );
}
