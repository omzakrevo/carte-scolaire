import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/license.dart';
import '../widgets/common.dart';

/// Logo de l'application.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/icon/logo_512.png', width: size, height: size, filterQuality: FilterQuality.medium);
}

/// Fond commun des écrans d'accueil (création du mot de passe, verrouillage).
class _AuthFrame extends StatelessWidget {
  final List<Widget> children;
  const _AuthFrame({required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF23368A), Color(0xFF101A45)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: AppLogo(size: 84)),
                        const SizedBox(height: 10),
                        Text('Carte Scolaire',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 20),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  const _PasswordField({required this.controller, required this.label, this.onSubmitted, this.autofocus = false});

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: _hidden,
        autofocus: widget.autofocus,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            tooltip: _hidden ? 'Afficher' : 'Masquer',
            onPressed: () => setState(() => _hidden = !_hidden),
            icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
          ),
        ),
      );
}

/// Premier lancement : choisir le mot de passe de l'application.
class SetupPasswordScreen extends StatefulWidget {
  const SetupPasswordScreen({super.key});

  @override
  State<SetupPasswordScreen> createState() => _SetupPasswordScreenState();
}

class _SetupPasswordScreenState extends State<SetupPasswordScreen> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    if (_a.text.length < 4) {
      setState(() => _error = 'Choisissez au moins 4 caractères.');
      return;
    }
    if (_a.text != _b.text) {
      setState(() => _error = 'Les deux mots de passe ne sont pas identiques.');
      return;
    }
    setState(() => _busy = true);
    await LicenseScope.read(context).setPassword(_a.text);
  }

  @override
  Widget build(BuildContext context) => _AuthFrame(children: [
        const Text(
          'Bienvenue ! Choisissez un mot de passe pour protéger l\'application, vos projets et les photos des élèves.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        _PasswordField(controller: _a, label: 'Mot de passe', autofocus: true),
        const SizedBox(height: 12),
        _PasswordField(controller: _b, label: 'Confirmer le mot de passe', onSubmitted: (_) => _submit()),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: _busy ? null : _submit,
          child: const Text('Créer le mot de passe'),
        ),
      ]);
}

/// Écran de verrouillage à l'ouverture.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _c = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await LicenseScope.read(context).unlock(_c.text);
    if (!ok && mounted) {
      setState(() {
        _busy = false;
        _error = 'Mot de passe incorrect.';
        _c.clear();
      });
    }
  }

  Future<void> _forgot() async {
    final lm = LicenseScope.read(context);
    final code = TextEditingController();
    final pwd = TextEditingController();
    String? err;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Mot de passe oublié'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Envoyez l\'identifiant de cet appareil à l\'administrateur : il vous renverra un code '
                    'de réinitialisation valable 7 jours.'),
                const SizedBox(height: 12),
                _DeviceIdBox(id: lm.deviceId),
                const SizedBox(height: 12),
                TextField(
                  controller: code,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Code de réinitialisation'),
                ),
                const SizedBox(height: 12),
                _PasswordField(controller: pwd, label: 'Nouveau mot de passe'),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(err!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
            FilledButton(
              onPressed: () async {
                if (pwd.text.length < 4) {
                  set(() => err = 'Le nouveau mot de passe doit faire au moins 4 caractères.');
                  return;
                }
                final e = await lm.resetPassword(code.text, pwd.text);
                if (e != null) {
                  set(() => err = e);
                } else if (c.mounted) {
                  Navigator.pop(c);
                }
              },
              child: const Text('Réinitialiser'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _AuthFrame(children: [
        const Text('Entrez votre mot de passe pour ouvrir l\'application.', textAlign: TextAlign.center),
        const SizedBox(height: 18),
        _PasswordField(controller: _c, label: 'Mot de passe', autofocus: true, onSubmitted: (_) => _submit()),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: _busy ? null : _submit,
          child: const Text('Ouvrir'),
        ),
        const SizedBox(height: 6),
        TextButton(onPressed: _forgot, child: const Text('Mot de passe oublié ?')),
      ]);
}

class _DeviceIdBox extends StatelessWidget {
  final String id;
  const _DeviceIdBox({required this.id});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Identifiant de l\'appareil', style: Theme.of(context).textTheme.labelMedium),
            SelectableText(id,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2, fontFamily: 'monospace')),
          ]),
        ),
        IconButton(
          tooltip: 'Copier',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: id));
            if (context.mounted) toast(context, 'Identifiant copié.');
          },
          icon: const Icon(Icons.copy),
        ),
      ]),
    );
  }
}

/// Licence : état, identifiant de l'appareil, activation d'un code.
class LicenseScreen extends StatefulWidget {
  /// Premier lancement : propose de commencer l'essai.
  final bool onboarding;
  const LicenseScreen({super.key, this.onboarding = false});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _activate() async {
    final lm = LicenseScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final e = await lm.activate(_code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = e;
    });
    if (e == null) {
      toast(context, 'Licence activée : ${lm.statusLabel}.');
      if (widget.onboarding) await lm.markWelcomed();
      if (mounted && !widget.onboarding) Navigator.of(context).maybePop();
    }
  }

  Future<void> _changePassword() async {
    final lm = LicenseScope.read(context);
    final old = TextEditingController();
    final a = TextEditingController();
    String? err;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Changer le mot de passe'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _PasswordField(controller: old, label: 'Mot de passe actuel'),
              const SizedBox(height: 12),
              _PasswordField(controller: a, label: 'Nouveau mot de passe'),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                if (!await lm.unlock(old.text)) {
                  set(() => err = 'Mot de passe actuel incorrect.');
                  return;
                }
                if (a.text.length < 4) {
                  set(() => err = 'Au moins 4 caractères.');
                  return;
                }
                await lm.setPassword(a.text);
                if (c.mounted) Navigator.pop(c);
                if (mounted) toast(context, 'Mot de passe modifié.');
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lm = LicenseScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ok = lm.isLicensed;
    final message = 'Bonjour, je souhaite activer Carte Scolaire. Identifiant de mon appareil : ${lm.deviceId}';

    final body = ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.onboarding) ...[
          const Center(child: AppLogo(size: 80)),
          const SizedBox(height: 12),
          Text('Activer Carte Scolaire',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ok ? const Color(0xFFE5F4EA) : const Color(0xFFFFF1E6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(ok ? Icons.verified : Icons.hourglass_bottom,
                color: ok ? const Color(0xFF0B6B3A) : const Color(0xFFB25E00), size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lm.statusLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1B1F24))),
                Text(
                  ok
                      ? (lm.daysLeft != null ? 'Il reste ${lm.daysLeft} jours.' : 'Merci pour votre confiance.')
                      : 'Toutes les fonctions sont disponibles, mais les cartes générées portent le filigrane « VERSION D\'ESSAI ».',
                  style: const TextStyle(color: Color(0xFF3B434D)),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        Text('1. Envoyez cet identifiant au vendeur', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _DeviceIdBox(id: lm.deviceId),
        const SizedBox(height: 8),
        Row(children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(6),
            child: QrImageView(data: lm.deviceId, size: 96, padding: EdgeInsets.zero),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                  'Licence d\'un mois, d\'un an ou définitive. Le code reçu ne fonctionne que sur cet appareil.'),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: message));
                  if (context.mounted) toast(context, 'Message copié : collez-le dans WhatsApp ou SMS.');
                },
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Copier le message de demande'),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 20),
        Text('2. Collez le code de licence reçu', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Code de licence',
            suffixIcon: IconButton(
              tooltip: 'Coller',
              icon: const Icon(Icons.content_paste),
              onPressed: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                if (d?.text != null) _code.text = d!.text!;
              },
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: _busy ? null : _activate,
          icon: const Icon(Icons.key),
          label: const Text('Activer la licence'),
        ),
        if (widget.onboarding) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: () => lm.markWelcomed(),
            child: const Text('Essayer gratuitement (cartes avec filigrane)'),
          ),
        ] else ...[
          const Divider(height: 36),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.password),
            title: const Text('Changer le mot de passe'),
            onTap: _changePassword,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: const Text('Verrouiller maintenant'),
            onTap: () {
              Navigator.of(context).maybePop();
              lm.lock();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync),
            title: const Text('Vérifier la licence en ligne'),
            subtitle: Text(lm.registryChecked == null
                ? 'Jamais vérifiée (nécessite Internet)'
                : 'Dernière vérification : ${lm.registryChecked!.day}/${lm.registryChecked!.month}/${lm.registryChecked!.year}'),
            onTap: () async {
              await lm.refreshRegistry();
              if (context.mounted) toast(context, lm.statusLabel);
            },
          ),
        ],
      ],
    );

    if (widget.onboarding) {
      return Scaffold(
          body: SafeArea(
              child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: body))));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Licence et sécurité')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: body)),
    );
  }
}
