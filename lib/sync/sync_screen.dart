import 'package:flutter/material.dart';

import '../services/license.dart';
import '../widgets/common.dart';
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
      text = 'Option active : connectez ce poste à votre compte.';
    } else if (sync.running) {
      text = 'Synchronisation… ${sync.total == 0 ? '' : '${sync.done}/${sync.total}'}';
    } else {
      text = '${sync.email} · ${sync.lastError != null ? 'erreur' : 'synchronisé ${_ago(sync.lastSync)}'}';
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
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _mail = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _init = false;
  String? _msg;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = SyncScope.maybeOf(context);
    if (!_init && s != null && s.loaded) {
      _init = true;
      _url.text = s.url;
      _key.text = s.anonKey;
      _mail.text = s.email;
    }
  }

  Future<void> _connect(SyncController s, {bool create = false}) async {
    if (_url.text.trim().isEmpty || _key.text.trim().isEmpty || _mail.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _msg = 'Remplissez l\'adresse du serveur, la clé publique, l\'e-mail et le mot de passe.');
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    final m = await s.connect(_url.text, _key.text, _mail.text, _pass.text, create: create);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _msg = m;
      if (s.connected) _pass.clear();
    });
    if (m == null && mounted) await runSync(context, s);
  }

  @override
  Widget build(BuildContext context) {
    final s = SyncScope.maybeOf(context)!;
    final lm = LicenseScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Multi-appareil')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Section(
          title: 'Le même compte sur l\'ordinateur et le téléphone',
          subtitle: 'Projets, fiches, photos, notes, bulletins et présences sont envoyés sur votre serveur '
              'et récupérés sur vos autres appareils. Chaque appareil garde sa propre licence.',
          children: [
            if (!s.allowed) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: const Text('Option payante non activée sur cet appareil'),
                subtitle: Text(
                    'Demandez l\'option « Multi-appareil » au vendeur pour chaque appareil (ordinateur, téléphone) '
                    'en donnant l\'identifiant ci-dessous. ${lm.isLicensed ? '' : 'Il faut une licence active.'}'),
              ),
              SelectableText('Identifiant de cet appareil : ${lm.deviceId}',
                  style: theme.textTheme.titleSmall?.copyWith(fontFamily: 'monospace')),
            ] else if (s.connected) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_circle_outlined, size: 32),
                title: Text(s.email),
                subtitle: Text('${s.url}\nDernière synchronisation : ${_ago(s.lastSync)}'),
                isThreeLine: true,
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
                OutlinedButton.icon(
                  onPressed: s.running
                      ? null
                      : () async {
                          if (await confirm(context, 'Déconnecter cet appareil ?',
                              'Les données restent sur l\'appareil, mais ne seront plus synchronisées.',
                              ok: 'Déconnecter')) {
                            await s.disconnect();
                          }
                        },
                  icon: const Icon(Icons.logout),
                  label: const Text('Se déconnecter'),
                ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.auto,
                title: const Text('Synchroniser automatiquement'),
                subtitle: const Text('Au démarrage puis toutes les 10 minutes, quand vous ne saisissez rien.'),
                onChanged: s.setAuto,
              ),
            ] else ...[
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                    labelText: 'Adresse du serveur', hintText: 'https://supabase.mondomaine.com'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _key,
                decoration: const InputDecoration(
                    labelText: 'Clé publique (anon key)', helperText: 'Donnée par l\'administrateur du serveur'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _mail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail du compte'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mot de passe du compte'),
                onSubmitted: (_) => _connect(s),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _connect(s),
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: const Text('Se connecter'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _connect(s, create: true),
                  child: const Text('Créer le compte'),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Utilisez le même e-mail et le même mot de passe sur l\'ordinateur et sur le téléphone. '
                'Au premier passage, les données des deux appareils sont réunies.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_msg!, style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ]),
    );
  }
}
