import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'card_designs.dart';

// Modèles de cartes de visite et de membre.
// Inspirés des tendances actuelles (bande diagonale avec photo, collage hexagonal,
// nom dans un bandeau + QR, cercle illustré, liste de services avec galerie),
// dessinés pour l'application : couleurs, textes et images viennent de la structure.

Uint8List? _gal(CardCtx c, int i) => c.school.gallery.isEmpty ? null : c.school.gallery[i % c.school.gallery.length];

/// Image de présentation, ou dégradé avec icône si la galerie est vide.
Widget _picture(CardCtx c, int i, {BoxFit fit = BoxFit.cover}) {
  final b = _gal(c, i);
  if (b != null) return Image.memory(b, fit: fit, gaplessPlayback: true);
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(c.primary, Colors.white, 0.35)!, Color.lerp(c.secondary, Colors.black, 0.1)!],
      ),
    ),
    child: Center(child: Icon(Icons.image_outlined, color: Colors.white70, size: 6 * c.u)),
  );
}

String _orgName(CardCtx c) => c.school.name.isNotEmpty ? c.school.name : c.school.shortName;

/// Coordonnées de la personne (téléphone, e-mail, adresse) puis site web de la structure.
List<(IconData, String)> _contacts(CardCtx c, {bool web = true}) => [
      if (c.t.shows('contact') && c.s.contact.isNotEmpty) (Icons.phone_in_talk, c.s.contact),
      if (c.t.shows('email') && c.s.email.isNotEmpty) (Icons.alternate_email, c.s.email),
      if (c.t.shows('adresse') && c.s.adresse.isNotEmpty) (Icons.location_on, c.s.adresse),
      if (web && c.school.website.isNotEmpty) (Icons.language, c.school.website),
      if (c.t.shows('matricule') && c.s.matricule.isNotEmpty) (Icons.tag, c.s.matricule),
    ];

Widget _iconRow(CardCtx c, IconData icon, String text,
    {required Color iconBg, required Color iconFg, required Color textColor, double size = 1.9}) {
  final u = c.u;
  final k = size * c.t.textScale;
  return Padding(
    padding: EdgeInsets.only(bottom: 0.7 * u * c.t.textScale),
    child: Row(children: [
      Container(
        width: k * 1.6 * u,
        height: k * 1.6 * u,
        decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
        child: Icon(icon, size: k * 1.0 * u, color: iconFg),
      ),
      SizedBox(width: 1 * u),
      Expanded(child: c.line(text, c.st(k, color: textColor, weight: FontWeight.w600))),
    ]),
  );
}

Widget _contactList(CardCtx c,
    {required Color iconBg, required Color iconFg, required Color textColor, double size = 1.9, bool web = true}) {
  return c.layer(
    'info',
    c.fit(
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, t) in _contacts(c, web: web))
          _iconRow(c, i, t, iconBg: iconBg, iconFg: iconFg, textColor: textColor, size: size),
      ]),
      align: Alignment.centerLeft,
    ),
    origin: Alignment.centerLeft,
  );
}

Widget _services(CardCtx c, {required Color bullet, required Color textColor, double size = 1.75, int max = 6}) {
  final list = c.school.serviceList.take(max).toList();
  if (list.isEmpty) return const SizedBox();
  final u = c.u;
  final k = size * c.t.textScale;
  return c.fit(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    for (final e in list)
      Padding(
        padding: EdgeInsets.only(bottom: 0.45 * u),
        child: Row(children: [
          Icon(Icons.check_circle, size: k * 1.05 * u, color: bullet),
          SizedBox(width: 0.7 * u),
          Expanded(child: c.line(e.toUpperCase(), c.st(k * 0.92, color: textColor, weight: FontWeight.w800))),
        ]),
      ),
  ]));
}

/// Nom en grand et fonction.
Widget _name(CardCtx c, {required Color color, required Color roleColor, double size = 3.3, bool upper = true}) {
  final n = upper ? '${c.s.prenom} ${c.s.nom.toUpperCase()}'.trim() : '${c.s.prenom} ${c.s.nom}'.trim();
  return c.layer(
    'name',
    Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (c.t.shows('nomPrenom') && n.isNotEmpty)
        c.line(n, c.st(size * c.t.textScale, color: color, weight: FontWeight.w900)),
      if (c.t.shows('service') && c.s.service.isNotEmpty)
        c.line(c.s.service.toUpperCase(),
            c.st(1.7 * c.t.textScale, color: roleColor, weight: FontWeight.w700, spacing: 0.12)),
    ]),
    origin: Alignment.topLeft,
  );
}

Widget _brand(CardCtx c, {required Color nameColor, required Color sloganColor, double logo = 10, bool row = true}) {
  final u = c.u;
  final text = Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: row ? CrossAxisAlignment.start : CrossAxisAlignment.center,
    children: [
      c.line(_orgName(c).toUpperCase(), c.st(2.6, color: nameColor, weight: FontWeight.w900),
          align: row ? Alignment.centerLeft : Alignment.center),
      if (c.school.slogan.isNotEmpty)
        c.line(c.school.slogan, c.st(1.35, color: sloganColor, weight: FontWeight.w600, italic: true),
            align: row ? Alignment.centerLeft : Alignment.center),
    ],
  );
  if (!row) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      c.logo(logo * u, fallbackBg: c.primary),
      SizedBox(height: 0.8 * u),
      c.layer('header', text),
    ]);
  }
  return Row(children: [
    c.logo(logo * u, fallbackBg: c.primary),
    SizedBox(width: 1.4 * u),
    Expanded(child: c.layer('header', text, origin: Alignment.centerLeft)),
  ]);
}

class _PathClipper extends CustomClipper<Path> {
  final Path Function(Size s) build;
  _PathClipper(this.build);
  @override
  Path getClip(Size size) => build(size);
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => true;
}

Path _hexagon(Size s) {
  final w = s.width, h = s.height;
  return Path()
    ..moveTo(w * 0.25, 0)
    ..lineTo(w * 0.75, 0)
    ..lineTo(w, h * 0.5)
    ..lineTo(w * 0.75, h)
    ..lineTo(w * 0.25, h)
    ..lineTo(0, h * 0.5)
    ..close();
}

/// Version portrait commune : en-tête coloré, puis contenu.
Widget _portrait(CardCtx c, {required Widget top, required Widget body, Color? topColor}) => Container(
      color: Colors.white,
      child: Column(children: [
        Container(
          height: c.h * 0.38,
          width: double.infinity,
          color: topColor ?? c.primary,
          padding: EdgeInsets.all(2.5 * c.u),
          child: top,
        ),
        Container(height: 0.8 * c.u, color: c.accent),
        Expanded(child: Padding(padding: EdgeInsets.all(3 * c.u), child: body)),
      ]),
    );

// ---------------------------------------------------------------------------
// 1. Bande diagonale avec image à droite.
Widget visiteDiagonale(CardCtx c) {
  final u = c.u;
  const dark = Color(0xFF1B1F24);
  if (!c.landscape) {
    return _portrait(c,
        top: ClipRect(child: Stack(fit: StackFit.expand, children: [_picture(c, 0)])),
        body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _brand(c, nameColor: c.primary, sloganColor: dark, logo: 8),
          SizedBox(height: 1.5 * u),
          _name(c, color: dark, roleColor: c.primary),
          SizedBox(height: 1.2 * u),
          Expanded(child: _contactList(c, iconBg: c.primary, iconFg: c.on(c.primary), textColor: dark)),
          if (c.t.showQr) Align(alignment: Alignment.bottomRight, child: c.qr(11 * u)),
        ]));
  }
  return Container(
    color: Colors.white,
    child: Stack(children: [
      // Bande diagonale colorée + image découpée en biais.
      Positioned.fill(
        child: ClipPath(
          clipper: _PathClipper((s) => Path()
            ..moveTo(s.width * 0.56, s.height)
            ..lineTo(s.width * 0.78, 0)
            ..lineTo(s.width, 0)
            ..lineTo(s.width, s.height)
            ..close()),
          child: Container(color: c.primary),
        ),
      ),
      Positioned.fill(
        child: ClipPath(
          clipper: _PathClipper((s) => Path()
            ..moveTo(s.width * 0.62, s.height)
            ..lineTo(s.width * 0.83, 0)
            ..lineTo(s.width, 0)
            ..lineTo(s.width, s.height)
            ..close()),
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: c.w * 0.45, height: c.h, child: _picture(c, 0)),
          ),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(3 * u, 2.5 * u, c.w * 0.4, 2 * u),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _brand(c, nameColor: c.primary, sloganColor: dark, logo: 8.5),
          SizedBox(height: 1.6 * u),
          _name(c, color: dark, roleColor: c.primary),
          if (c.school.slogan.isNotEmpty || c.school.services.isNotEmpty) ...[
            SizedBox(height: 0.8 * u),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 1.2 * u, vertical: 0.35 * u),
              decoration: BoxDecoration(
                border: Border.all(color: c.primary, width: 0.25 * u),
                borderRadius: BorderRadius.circular(3 * u),
              ),
              child: c.line(
                  (c.school.serviceList.isNotEmpty ? c.school.serviceList.take(3).join(' • ') : c.school.slogan)
                      .toUpperCase(),
                  c.st(1.3, color: dark, weight: FontWeight.w800, spacing: 0.1)),
            ),
          ],
          SizedBox(height: 1.2 * u),
          Expanded(child: _contactList(c, iconBg: c.primary, iconFg: c.on(c.primary), textColor: dark, size: 1.8)),
        ]),
      ),
      if (c.t.showQr) Positioned(right: 2 * u, bottom: 2 * u, child: c.qr(10 * u)),
    ]),
  );
}

// ---------------------------------------------------------------------------
// 2. Collage d'images hexagonales sur bande colorée, services et barre de contact.
Widget visiteHexagone(CardCtx c) {
  final u = c.u;
  const dark = Color(0xFF1B1F24);
  final barColor = Color.lerp(c.primary, Colors.black, 0.35)!;
  final contactBar = Container(
    height: c.h * (c.landscape ? 0.3 : 0.2),
    padding: EdgeInsets.symmetric(horizontal: 1.6 * u, vertical: 0.8 * u),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [barColor, c.primary]),
      borderRadius: BorderRadius.circular(1.6 * u),
    ),
    child: _contactList(c, iconBg: Colors.white, iconFg: c.primary, textColor: Colors.white, size: 1.55),
  );
  Widget hex(int i, double size) => SizedBox(
        width: size,
        height: size * 0.87,
        child: ClipPath(clipper: _PathClipper(_hexagon), child: _picture(c, i)),
      );
  if (!c.landscape) {
    return _portrait(c,
        top: Center(child: _brand(c, nameColor: c.on(c.primary), sloganColor: c.on(c.primary), logo: 10, row: false)),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _name(c, color: dark, roleColor: c.primary),
          SizedBox(height: 1 * u),
          Expanded(child: _services(c, bullet: c.primary, textColor: dark)),
          contactBar,
        ]));
  }
  final side = c.w * 0.34;
  return Container(
    color: Colors.white,
    child: Row(children: [
      Expanded(
        child: Padding(
          padding: EdgeInsets.fromLTRB(2.6 * u, 2.2 * u, 1.6 * u, 2 * u),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _brand(c, nameColor: c.primary, sloganColor: dark, logo: 9),
            SizedBox(height: 1 * u),
            _name(c, color: dark, roleColor: c.primary, size: 2.6),
            SizedBox(height: 0.8 * u),
            Expanded(child: _services(c, bullet: c.primary, textColor: dark, size: 1.55, max: 5)),
            SizedBox(height: 0.6 * u),
            contactBar,
          ]),
        ),
      ),
      SizedBox(
        width: side,
        child: Stack(children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [c.primary, barColor],
                ),
              ),
            ),
          ),
          Positioned(left: side * 0.12, top: 0, bottom: 0, child: Container(width: 1.6 * u, color: c.secondary)),
          Positioned(
              left: side * 0.12 + 2.2 * u, top: 0, bottom: 0, child: Container(width: 0.6 * u, color: Colors.white)),
          Positioned(right: side * 0.1, top: c.h * 0.04, child: hex(0, side * 0.55)),
          Positioned(left: side * 0.02, top: c.h * 0.36, child: hex(1, side * 0.55)),
          Positioned(right: side * 0.1, top: c.h * 0.66, child: hex(2, side * 0.55)),
          if (c.t.showQr) Positioned(right: 1 * u, bottom: 1 * u, child: c.qr(8 * u)),
        ]),
      ),
    ]),
  );
}

// ---------------------------------------------------------------------------
// 3. Nom dans un bandeau, QR encadré, coordonnées séparées par un pointillé.
class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = s.width;
    for (double y = 0; y < s.height; y += s.width * 5) {
      canvas.drawLine(Offset(s.width / 2, y), Offset(s.width / 2, math.min(s.height, y + s.width * 2.5)), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter o) => o.color != color;
}

Widget visiteBandeauNom(CardCtx c) {
  final u = c.u;
  final dark = c.secondary;
  final pill = c.layer(
    'name',
    Container(
      padding: EdgeInsets.fromLTRB(1.2 * u, 0.9 * u, 2 * u, 0.9 * u),
      decoration: BoxDecoration(
        color: dark,
        borderRadius: BorderRadius.horizontal(left: Radius.circular(4 * u)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 4.2 * u,
          height: 4.2 * u,
          decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          child: c.s.photo != null
              ? Image.memory(c.s.photo!, fit: BoxFit.cover)
              : Icon(Icons.person, color: c.on(c.primary), size: 3 * u),
        ),
        SizedBox(width: 1.2 * u),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (c.t.shows('nomPrenom'))
              c.line('${c.s.prenom} ${c.s.nom}'.trim().toUpperCase(),
                  c.st(2.2 * c.t.textScale, color: c.on(dark), weight: FontWeight.w900)),
            if (c.t.shows('service') && c.s.service.isNotEmpty)
              c.line(c.s.service, c.st(1.4 * c.t.textScale, color: c.primary, weight: FontWeight.w700, italic: true)),
          ]),
        ),
      ]),
    ),
    origin: Alignment.centerRight,
  );
  final qr = c.t.showQr
      ? Container(
          padding: EdgeInsets.all(0.7 * u),
          decoration: BoxDecoration(border: Border.all(color: c.primary, width: 0.4 * u)),
          child: c.qr(c.landscape ? 13 * u : 14 * u),
        )
      : c.logo(13 * u);
  if (!c.landscape) {
    return Container(
      color: Colors.white,
      child: Column(children: [
        Container(height: 1.6 * u, color: dark),
        Container(height: 0.5 * u, color: c.primary),
        Padding(padding: EdgeInsets.all(2.5 * u), child: _brand(c, nameColor: dark, sloganColor: c.primary, logo: 9)),
        Align(alignment: Alignment.centerRight, child: pill),
        SizedBox(height: 2 * u),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 3 * u),
            child: _contactList(c, iconBg: dark, iconFg: Colors.white, textColor: const Color(0xFF22262B)),
          ),
        ),
        Padding(padding: EdgeInsets.only(bottom: 2.5 * u), child: qr),
      ]),
    );
  }
  return Container(
    color: Colors.white,
    child: Row(children: [
      Container(width: c.w * 0.08, color: dark),
      Container(width: 0.6 * u, color: c.primary),
      Expanded(
        child: Column(children: [
          SizedBox(height: 2.2 * u),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 2.4 * u),
            Expanded(child: _brand(c, nameColor: dark, sloganColor: c.primary, logo: 8)),
            SizedBox(width: 1 * u),
            Flexible(child: pill),
          ]),
          SizedBox(height: 1.6 * u),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(3 * u, 0, 2.5 * u, 2.5 * u),
              child: Row(children: [
                qr,
                SizedBox(width: 2.4 * u),
                SizedBox(width: 0.25 * u, child: CustomPaint(painter: _DashPainter(const Color(0xFF555B63)))),
                SizedBox(width: 2.4 * u),
                Expanded(
                    child: _contactList(c, iconBg: dark, iconFg: Colors.white, textColor: const Color(0xFF22262B))),
              ]),
            ),
          ),
        ]),
      ),
    ]),
  );
}

// ---------------------------------------------------------------------------
// 4. Grand cercle illustré bordé d'arcs, services cochés.
class _ArcsPainter extends CustomPainter {
  final Color a, b;
  _ArcsPainter(this.a, this.b);
  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width * 0.5, s.height * 0.5);
    final r = s.shortestSide * 0.5;
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 1.03),
        -0.6,
        2.6,
        false,
        Paint()
          ..color = a
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.12);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 1.14),
        2.2,
        2.4,
        false,
        Paint()
          ..color = b
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.07);
  }

  @override
  bool shouldRepaint(_ArcsPainter o) => o.a != a || o.b != b;
}

Widget visiteCercle(CardCtx c) {
  final u = c.u;
  final dark = c.secondary;
  Widget circle(double d) => SizedBox(
        width: d,
        height: d,
        child: Stack(fit: StackFit.expand, children: [
          Padding(padding: EdgeInsets.all(d * 0.08), child: ClipOval(child: _picture(c, 0))),
          CustomPaint(painter: _ArcsPainter(c.primary, c.accent)),
        ]),
      );
  final person = c.layer(
    'name',
    Row(mainAxisSize: MainAxisSize.min, children: [
      if (c.t.shows('service') && c.s.service.isNotEmpty)
        Text('${c.s.service.toUpperCase()} : ', style: c.st(1.6 * c.t.textScale, color: dark, weight: FontWeight.w800)),
      if (c.t.shows('nomPrenom'))
        Flexible(
          child: c.line('${c.s.prenom} ${c.s.nom}'.trim().toUpperCase(),
              c.st(1.7 * c.t.textScale, color: c.primary, weight: FontWeight.w900)),
        ),
    ]),
    origin: Alignment.centerLeft,
  );
  final footer = Container(
    padding: EdgeInsets.fromLTRB(2.6 * u, 0.8 * u, 2 * u, 0.8 * u),
    child: _contactList(c, iconBg: dark, iconFg: Colors.white, textColor: const Color(0xFF22262B), size: 1.45),
  );
  if (!c.landscape) {
    return Container(
      color: Colors.white,
      child: Column(children: [
        SizedBox(height: 2 * u),
        circle(c.w * 0.62),
        Padding(padding: EdgeInsets.all(2 * u), child: _brand(c, nameColor: dark, sloganColor: c.primary, logo: 7)),
        Padding(padding: EdgeInsets.symmetric(horizontal: 2.6 * u), child: person),
        SizedBox(height: 1 * u),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 2.6 * u),
            child: _services(c, bullet: c.accent, textColor: dark, size: 1.5),
          ),
        ),
        footer,
        Container(height: 1 * u, color: dark),
      ]),
    );
  }
  return Container(
    color: Colors.white,
    child: Stack(children: [
      Positioned(
        right: -c.h * 0.15,
        bottom: -c.h * 0.25,
        child: Container(
          width: c.h * 0.95,
          height: c.h * 0.95,
          decoration: BoxDecoration(color: dark, shape: BoxShape.circle),
        ),
      ),
      Positioned(right: c.w * 0.03, top: c.h * 0.06, child: circle(c.h * 0.78)),
      Column(children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(2.6 * u, 2.2 * u, c.h * 0.88, 0.5 * u),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _brand(c, nameColor: dark, sloganColor: c.primary, logo: 7.5),
              SizedBox(height: 0.6 * u),
              Container(height: 0.35 * u, width: 22 * u, color: dark),
              SizedBox(height: 0.6 * u),
              person,
              SizedBox(height: 0.8 * u),
              Expanded(child: _services(c, bullet: c.accent, textColor: dark, size: 1.45, max: 6)),
            ]),
          ),
        ),
        Padding(padding: EdgeInsets.only(right: c.h * 0.8), child: footer),
        Row(children: [
          Expanded(child: Container(height: 0.9 * u, color: dark)),
          Container(width: c.w * 0.2, height: 0.9 * u, color: c.accent),
        ]),
      ]),
      if (c.t.showQr) Positioned(left: c.w * 0.5, bottom: 2.4 * u, child: c.qr(8 * u)),
    ]),
  );
}

// ---------------------------------------------------------------------------
// 5. Services et contacts à gauche, galerie d'images sur fond coloré à droite.
Widget visiteGalerie(CardCtx c) {
  final u = c.u;
  final dark = c.secondary;
  Widget heading(String t) => Container(
        margin: EdgeInsets.only(bottom: 0.7 * u),
        padding: EdgeInsets.symmetric(horizontal: 1.6 * u, vertical: 0.4 * u),
        decoration: BoxDecoration(
          color: c.primary,
          borderRadius: BorderRadius.horizontal(right: Radius.circular(2 * u)),
        ),
        child: c.line(t, c.st(1.6, color: c.on(c.primary), weight: FontWeight.w800)),
      );
  final left = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _brand(c, nameColor: dark, sloganColor: c.primary, logo: 7),
    SizedBox(height: 0.6 * u),
    _name(c, color: dark, roleColor: c.primary, size: 2.4),
    SizedBox(height: 0.8 * u),
    if (c.school.serviceList.isNotEmpty) ...[
      heading('Nos services'),
      Expanded(child: _services(c, bullet: c.primary, textColor: dark, size: 1.4, max: 6)),
    ] else
      const Spacer(),
    heading('Contacts'),
    _contactList(c, iconBg: c.primary, iconFg: c.on(c.primary), textColor: const Color(0xFF22262B), size: 1.4),
  ]);
  Widget grid(int cols, int rows) => Column(children: [
        for (var r = 0; r < rows; r++)
          Expanded(
            child: Row(children: [
              for (var k = 0; k < cols; k++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(0.5 * u),
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 0.3 * u)),
                      child: _picture(c, r * cols + k),
                    ),
                  ),
                ),
            ]),
          ),
      ]);
  final panel = Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [c.primary, Color.lerp(c.primary, Colors.black, 0.3)!],
      ),
    ),
    padding: EdgeInsets.all(1 * u),
    child: Stack(children: [
      Positioned.fill(child: grid(c.landscape ? 2 : 3, c.landscape ? 3 : 2)),
      if (c.t.showQr) Positioned(right: 0.5 * u, bottom: 0.5 * u, child: c.qr(8 * u)),
    ]),
  );
  if (!c.landscape) {
    return Container(
      color: Colors.white,
      child: Column(children: [
        SizedBox(height: c.h * 0.3, child: panel),
        Expanded(child: Padding(padding: EdgeInsets.all(2.4 * u), child: left)),
      ]),
    );
  }
  return Container(
    color: Colors.white,
    child: Row(children: [
      Expanded(child: Padding(padding: EdgeInsets.fromLTRB(2.4 * u, 2 * u, 1.6 * u, 1.6 * u), child: left)),
      SizedBox(width: c.w * 0.42, child: panel),
    ]),
  );
}

// ---------------------------------------------------------------------------
// Carte de membre : vagues bleu et or, photo ronde, image de fond en filigrane.
class _SwooshPainter extends CustomPainter {
  final Color a, b;
  _SwooshPainter(this.a, this.b);
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    Path wave(double off) => Path()
      ..moveTo(w * (0.35 + off), h)
      ..cubicTo(w * (0.6 + off), h * 0.92, w * (0.85 + off), h * 0.7, w * 1.02, h * (0.15 + off))
      ..lineTo(w * 1.02, h * (0.3 + off))
      ..cubicTo(w * (0.9 + off), h * 0.8, w * (0.7 + off), h * 1.0, w * (0.42 + off), h)
      ..close();
    canvas.drawPath(wave(0), Paint()..color = a);
    canvas.drawPath(wave(0.08), Paint()..color = b);
    canvas.drawPath(wave(0.16), Paint()..color = a.withValues(alpha: 0.85));
    canvas.drawRect(Rect.fromLTWH(0, h * 0.965, w, h * 0.035), Paint()..color = a);
  }

  @override
  bool shouldRepaint(_SwooshPainter o) => o.a != a || o.b != b;
}

Widget membreVague(CardCtx c) {
  final u = c.u;
  final bg = c.t.background;
  final photoSize = c.landscape ? c.h * 0.42 : c.w * 0.5;
  final photo = c.layer(
    'photo',
    Container(
      width: photoSize,
      height: photoSize,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.primary, width: 0.6 * u)),
      clipBehavior: Clip.antiAlias,
      child: c.s.photo != null
          ? Image.memory(c.s.photo!, fit: BoxFit.cover, gaplessPlayback: true)
          : Container(
              color: const Color(0xFFE4E7EB),
              child: Icon(Icons.person, color: const Color(0xFFA3ACB6), size: photoSize * 0.7)),
    ),
  );
  final head = c.layer(
    'title',
    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      c.line(
          c.t.title.toUpperCase(), c.st(3.3, color: const Color(0xFF111111), weight: FontWeight.w900, spacing: 0.15)),
      c.line(_orgName(c).toUpperCase(), c.st(2.2, color: c.primary, weight: FontWeight.w900)),
      if (c.year.isNotEmpty) c.line(c.year, c.st(1.4, color: c.primary, weight: FontWeight.w700)),
    ]),
    origin: Alignment.topLeft,
  );
  final info = c.layer(
    'info',
    c.info(label: const Color(0xFF2B2F36), value: const Color(0xFF111111), size: 2.0),
    origin: Alignment.topLeft,
  );
  return Container(
    color: Colors.white,
    child: Stack(children: [
      if (bg != null)
        Positioned.fill(
            child: Opacity(opacity: 0.18, child: Image.memory(bg, fit: BoxFit.cover, gaplessPlayback: true))),
      Positioned.fill(child: CustomPaint(painter: _SwooshPainter(c.primary, c.accent))),
      Padding(
        padding: EdgeInsets.fromLTRB(3 * u, 2.5 * u, 2.5 * u, 2.5 * u),
        child: c.landscape
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [c.logo(7 * u), SizedBox(width: 1.2 * u), Expanded(child: head)]),
                    SizedBox(height: 1.4 * u),
                    Expanded(child: info),
                  ]),
                ),
                SizedBox(width: 1.5 * u),
                Column(children: [
                  photo,
                  const Spacer(),
                  if (c.t.showQr) Padding(padding: EdgeInsets.only(bottom: 2 * u), child: c.qr(9 * u)),
                ]),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [c.logo(7 * u), SizedBox(width: 1.2 * u), Expanded(child: head)]),
                SizedBox(height: 1.5 * u),
                Center(child: photo),
                SizedBox(height: 1.5 * u),
                Expanded(child: info),
                if (c.t.showQr) c.qr(9 * u),
              ]),
      ),
    ]),
  );
}

// ---------------------------------------------------------------------------
// 7. Panneau courbe : marque à gauche, panneau coloré arrondi avec nom et contacts.
class _CurvePainter extends CustomPainter {
  final Color panel, stroke;
  final bool vertical;
  _CurvePainter(this.panel, this.stroke, {this.vertical = false});

  Path _edge(Size s, double shift) {
    final w = s.width, h = s.height;
    if (vertical) {
      return Path()
        ..moveTo(0, h * (0.42 + shift))
        ..cubicTo(w * 0.35, h * (0.34 + shift), w * 0.65, h * (0.5 + shift), w, h * (0.4 + shift))
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
    }
    return Path()
      ..moveTo(w * (0.5 + shift), 0)
      ..cubicTo(w * (0.38 + shift), h * 0.3, w * (0.5 + shift), h * 0.7, w * (0.4 + shift), h)
      ..lineTo(w, h)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawPath(_edge(s, -0.018), Paint()..color = stroke);
    canvas.drawPath(_edge(s, 0), Paint()..color = panel);
  }

  @override
  bool shouldRepaint(_CurvePainter o) => o.panel != panel || o.stroke != stroke || o.vertical != vertical;
}

Widget visiteCourbe(CardCtx c) {
  final u = c.u;
  final panel = c.primary;
  final fg = c.on(panel);
  final person = c.layer(
    'name',
    Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 5.4 * u,
        height: 5.4 * u,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.accent, width: 0.35 * u)),
        clipBehavior: Clip.antiAlias,
        child: c.s.photo != null
            ? Image.memory(c.s.photo!, fit: BoxFit.cover)
            : Icon(Icons.person, color: c.accent, size: 3.6 * u),
      ),
      SizedBox(width: 1.2 * u),
      Flexible(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (c.t.shows('nomPrenom'))
            c.line('${c.s.prenom} ${c.s.nom}'.trim().toUpperCase(),
                c.st(2.6 * c.t.textScale, color: fg, weight: FontWeight.w900)),
          if (c.t.shows('service') && c.s.service.isNotEmpty)
            c.line(c.s.service.toUpperCase(),
                c.st(1.5 * c.t.textScale, color: c.accent, weight: FontWeight.w700, spacing: 0.1)),
        ]),
      ),
    ]),
    origin: Alignment.centerLeft,
  );
  final contacts = c.layer(
    'info',
    c.fit(
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, t) in _contacts(c))
          Padding(
            padding: EdgeInsets.only(bottom: 0.8 * u * c.t.textScale),
            child: Row(children: [
              Container(
                width: 3.2 * u * c.t.textScale,
                height: 3.2 * u * c.t.textScale,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.accent, width: 0.3 * u)),
                child: Icon(i, size: 1.8 * u * c.t.textScale, color: c.accent),
              ),
              SizedBox(width: 1.2 * u),
              Expanded(child: c.line(t, c.st(1.75 * c.t.textScale, color: fg, weight: FontWeight.w500))),
            ]),
          ),
      ]),
      align: Alignment.centerLeft,
    ),
    origin: Alignment.centerLeft,
  );
  final brand = Column(mainAxisSize: MainAxisSize.min, children: [
    c.logo((c.landscape ? 15 : 13) * u, fallbackBg: c.primary),
    SizedBox(height: 1 * u),
    c.layer(
      'header',
      Column(mainAxisSize: MainAxisSize.min, children: [
        c.line(_orgName(c).toUpperCase(), c.st(2.4, color: c.secondary, weight: FontWeight.w900),
            align: Alignment.center),
        Container(
          margin: EdgeInsets.symmetric(vertical: 0.5 * u),
          width: 14 * u,
          height: 0.35 * u,
          color: c.accent,
        ),
        if (c.school.slogan.isNotEmpty)
          c.line(c.school.slogan.toUpperCase(), c.st(1.4, color: c.primary, weight: FontWeight.w800, italic: true),
              align: Alignment.center),
      ]),
    ),
  ]);
  final divider = Container(
    margin: EdgeInsets.symmetric(vertical: 1.2 * u),
    height: 0.3 * u,
    color: c.accent.withValues(alpha: 0.8),
  );
  if (!c.landscape) {
    return Container(
      color: Colors.white,
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _CurvePainter(panel, c.accent, vertical: true))),
        Column(children: [
          SizedBox(height: c.h * 0.04),
          SizedBox(height: c.h * 0.36, child: Center(child: brand)),
          const Spacer(),
          Padding(
            padding: EdgeInsets.fromLTRB(3 * u, 0, 3 * u, 3 * u),
            child: SizedBox(
              height: c.h * 0.44,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                person,
                divider,
                Expanded(child: contacts),
                if (c.t.showQr) Align(alignment: Alignment.centerRight, child: c.qr(9 * u)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
  return Container(
    color: Colors.white,
    child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _CurvePainter(panel, c.accent))),
      Row(children: [
        SizedBox(
          width: c.w * 0.42,
          child: Padding(
            padding: EdgeInsets.all(2.5 * u),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              brand,
              if (c.t.showQr) ...[SizedBox(height: 1.5 * u), c.qr(9 * u, dark: c.secondary)],
            ]),
          ),
        ),
        SizedBox(width: c.w * 0.06),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(1 * u, 3.5 * u, 3 * u, 3 * u),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              person,
              divider,
              Expanded(child: contacts),
            ]),
          ),
        ),
      ]),
    ]),
  );
}

// ---------------------------------------------------------------------------
// 8. Bandes verticales et demi-cercle portant le logo.
Widget visiteBandes(CardCtx c) {
  final u = c.u;
  final dark = c.secondary;
  final grad = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color.lerp(c.primary, Colors.white, 0.12)!, Color.lerp(c.primary, Colors.black, 0.35)!],
  );
  final name = _orgName(c).toUpperCase();
  final words = name.split(' ');
  final first = words.first;
  final rest = words.skip(1).join(' ');
  final title = c.layer(
    'header',
    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      c.line(first, c.st(4.4, color: c.primary, weight: FontWeight.w900)),
      if (rest.isNotEmpty) c.line(rest, c.st(2.8, color: dark, weight: FontWeight.w900, spacing: 0.25)),
      if (c.school.slogan.isNotEmpty) ...[
        SizedBox(height: 0.6 * u),
        Row(children: [
          Container(width: 2.5 * u, height: 0.25 * u, color: c.primary),
          SizedBox(width: 0.8 * u),
          Flexible(child: c.line(c.school.slogan, c.st(1.45, color: dark, weight: FontWeight.w600, italic: true))),
          SizedBox(width: 0.8 * u),
          Container(width: 2.5 * u, height: 0.25 * u, color: c.primary),
        ]),
      ],
    ]),
    origin: Alignment.centerLeft,
  );
  final person = _name(c, color: dark, roleColor: c.primary, size: 2.6);
  final contactBar = c.layer(
    'info',
    Container(
      padding: EdgeInsets.symmetric(horizontal: 1.6 * u, vertical: 1 * u),
      decoration: BoxDecoration(gradient: grad, borderRadius: BorderRadius.circular(1.6 * u)),
      child: c.fit(
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, t) in _contacts(c))
            _iconRow(c, i, t, iconBg: Colors.white, iconFg: c.primary, textColor: Colors.white, size: 1.55),
        ]),
        align: Alignment.centerLeft,
      ),
    ),
    origin: Alignment.bottomLeft,
  );
  final logoDisc = Container(
    width: c.landscape ? c.h * 0.56 : c.w * 0.5,
    height: c.landscape ? c.h * 0.56 : c.w * 0.5,
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 1.5 * u, offset: Offset(0, 0.4 * u))],
    ),
    alignment: Alignment.center,
    child: c.logo((c.landscape ? c.h * 0.36 : c.w * 0.32), fallbackBg: c.primary),
  );
  if (!c.landscape) {
    return Container(
      color: Colors.white,
      child: Stack(children: [
        Positioned(left: 0, right: 0, top: 0, height: c.h * 0.2, child: DecoratedBox(decoration: BoxDecoration(gradient: grad))),
        Positioned(left: 0, right: 0, top: c.h * 0.2, height: c.h * 0.035, child: ColoredBox(color: dark)),
        Positioned(top: c.h * 0.2 - c.w * 0.25 + c.h * 0.017, left: c.w * 0.25, child: logoDisc),
        Positioned.fill(
          top: c.h * 0.2 + c.w * 0.27,
          child: Padding(
            padding: EdgeInsets.fromLTRB(3 * u, 1 * u, 3 * u, 2.5 * u),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title,
              SizedBox(height: 1.2 * u),
              person,
              const Spacer(),
              contactBar,
            ]),
          ),
        ),
      ]),
    );
  }
  return Container(
    color: Colors.white,
    child: Stack(children: [
      Positioned(left: 0, top: 0, bottom: 0, width: c.w * 0.15, child: DecoratedBox(decoration: BoxDecoration(gradient: grad))),
      Positioned(left: c.w * 0.15, top: 0, bottom: 0, width: c.w * 0.035, child: ColoredBox(color: dark)),
      Positioned(right: 0, top: 0, width: c.w * 0.07, height: c.h * 0.16, child: DecoratedBox(decoration: BoxDecoration(gradient: grad))),
      Positioned(right: 0, bottom: 0, width: c.w * 0.025, height: c.h * 0.45, child: ColoredBox(color: c.primary)),
      Positioned(left: c.w * 0.167 - c.h * 0.28, top: c.h * 0.22, child: logoDisc),
      Positioned(
        left: c.w * 0.167 + c.h * 0.31,
        right: c.w * 0.06,
        top: 0,
        bottom: 0,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 2.6 * u),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            title,
            SizedBox(height: 1 * u),
            person,
            SizedBox(height: 1 * u),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: contactBar),
                if (c.t.showQr) ...[SizedBox(width: 1.2 * u), c.qr(10 * u, dark: dark)],
              ]),
            ),
          ]),
        ),
      ),
    ]),
  );
}

// ---------------------------------------------------------------------------
// 9. Face pleine couleur (recto) — et son verso sans la personne.
class _StripesPainter extends CustomPainter {
  final Color a, b;
  _StripesPainter(this.a, this.b);
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final p1 = Path()
      ..moveTo(w * 0.62, h)
      ..lineTo(w, h * 0.38)
      ..lineTo(w, h * 0.46)
      ..lineTo(w * 0.69, h)
      ..close();
    canvas.drawPath(p1, Paint()..color = a);
    final p2 = Path()
      ..moveTo(w * 0.72, h)
      ..lineTo(w, h * 0.55)
      ..lineTo(w, h * 0.585)
      ..lineTo(w * 0.745, h)
      ..close();
    canvas.drawPath(p2, Paint()..color = b);
    canvas.drawCircle(Offset(w * 0.08, h * 0.1), h * 0.42, Paint()..color = Colors.white.withValues(alpha: 0.05));
    canvas.drawCircle(Offset(w * 0.92, h * 0.05), h * 0.25, Paint()..color = Colors.white.withValues(alpha: 0.06));
  }

  @override
  bool shouldRepaint(_StripesPainter o) => o.a != a || o.b != b;
}

Widget _plein(CardCtx c, {required bool person}) {
  final u = c.u;
  final fg = c.on(c.primary);
  final services = c.school.serviceList;
  final brand = c.layer(
    'header',
    Column(mainAxisSize: MainAxisSize.min, children: [
      c.line(_orgName(c).toUpperCase(), c.st(c.landscape ? 4 : 3.4, color: fg, weight: FontWeight.w900, spacing: 0.15),
          align: Alignment.center),
      if (c.school.slogan.isNotEmpty) ...[
        SizedBox(height: 0.8 * u),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 2.4 * u, vertical: 0.55 * u),
          decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(0.8 * u)),
          child: c.line(c.school.slogan.toUpperCase(),
              c.st(1.45, color: c.on(c.accent), weight: FontWeight.w800, spacing: 0.1),
              align: Alignment.center),
        ),
      ],
      if (services.isNotEmpty) ...[
        SizedBox(height: 0.9 * u),
        c.line(services.take(4).join('  |  '), c.st(1.3, color: fg.withValues(alpha: 0.9), weight: FontWeight.w600),
            align: Alignment.center),
      ],
    ]),
  );
  final bottom = person
      ? c.layer(
          'name',
          Column(mainAxisSize: MainAxisSize.min, children: [
            if (c.t.shows('nomPrenom'))
              c.line('${c.s.prenom} ${c.s.nom}'.trim().toUpperCase(),
                  c.st(2.3 * c.t.textScale, color: fg, weight: FontWeight.w900), align: Alignment.center),
            c.line(
                [
                  if (c.t.shows('service') && c.s.service.isNotEmpty) c.s.service,
                  if (c.t.shows('contact') && c.s.contact.isNotEmpty) c.s.contact,
                ].join('  •  '),
                c.st(1.5 * c.t.textScale, color: c.accent, weight: FontWeight.w700),
                align: Alignment.center),
          ]),
        )
      : c.layer(
          'footer',
          c.line(
              [
                if (c.school.phone.isNotEmpty) c.school.phone,
                if (c.school.website.isNotEmpty) c.school.website,
                if (c.school.address.isNotEmpty) c.school.address,
              ].join('   •   '),
              c.st(1.45, color: fg.withValues(alpha: 0.92), weight: FontWeight.w600),
              align: Alignment.center),
        );
  return Container(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(-0.3, -0.4),
        radius: 1.3,
        colors: [Color.lerp(c.primary, Colors.white, 0.12)!, Color.lerp(c.primary, Colors.black, 0.35)!],
      ),
    ),
    child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _StripesPainter(c.accent, c.secondary == c.primary ? Colors.white54 : c.secondary))),
      Padding(
        padding: EdgeInsets.fromLTRB(4 * u, 3 * u, 4 * u, 2.6 * u),
        child: Column(children: [
          const Spacer(),
          c.logo((c.landscape ? 13 : 16) * u, fallbackBg: c.accent),
          SizedBox(height: 1.2 * u),
          brand,
          const Spacer(),
          bottom,
          if (person && c.t.showQr && !c.landscape) ...[SizedBox(height: 1 * u), c.qr(9 * u)],
        ]),
      ),
    ]),
  );
}

Widget visitePlein(CardCtx c) => _plein(c, person: true);

/// Verso : couleur pleine, logo, nom de la structure, slogan.
Widget versoLogo(CardCtx c) => _plein(c, person: false);

// ---------------------------------------------------------------------------
// Verso « Services et photos ».
Widget versoServices(CardCtx c) {
  final u = c.u;
  final dark = c.secondary;
  final n = c.school.gallery.isEmpty ? 4 : math.min(4, math.max(c.school.gallery.length, 3));
  final strip = c.layer(
    'photo',
    Row(children: [
      for (var i = 0; i < n; i++) ...[
        if (i > 0) SizedBox(width: 1 * u),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 0.45 * u),
              borderRadius: BorderRadius.circular(1.2 * u),
            ),
            clipBehavior: Clip.antiAlias,
            child: _picture(c, i),
          ),
        ),
      ],
    ]),
  );
  final services = c.school.serviceList;
  final half = (services.length / 2).ceil();
  Widget col(List<String> l) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        for (final e in l)
          Padding(
            padding: EdgeInsets.only(bottom: 0.9 * u),
            child: Row(children: [
              Icon(Icons.check_box, size: 2.3 * u, color: c.primary),
              SizedBox(width: 0.8 * u),
              Expanded(child: c.line(e.toUpperCase(), c.st(1.85, color: dark, weight: FontWeight.w800))),
            ]),
          ),
      ]);
  final serviceBlock = c.layer(
    'info',
    c.fit(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: EdgeInsets.symmetric(horizontal: 1.6 * u, vertical: 0.4 * u),
        decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(2 * u)),
        child: Text('NOS SERVICES', style: c.st(1.8, color: c.on(c.primary), weight: FontWeight.w900, spacing: 0.15)),
      ),
      SizedBox(height: 0.9 * u),
      if (services.isEmpty)
        c.line('Ajoutez vos services dans « Structure »', c.st(1.4, color: Colors.grey))
      else if (c.landscape && services.length > 3)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: col(services.take(half).toList())),
          SizedBox(width: 1.5 * u),
          Expanded(child: col(services.skip(half).toList())),
        ])
      else
        col(services.take(8).toList()),
    ])),
    origin: Alignment.topLeft,
  );
  final contacts = [
    if (c.school.phone.isNotEmpty) (Icons.phone_in_talk, c.school.phone),
    if (c.school.website.isNotEmpty) (Icons.language, c.school.website),
    if (c.school.address.isNotEmpty) (Icons.location_on, c.school.address),
  ];
  final bar = c.layer(
    'footer',
    Container(
      color: dark,
      padding: EdgeInsets.symmetric(horizontal: 2.5 * u, vertical: 0.9 * u),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        for (final (i, t) in contacts)
          Flexible(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(i, size: 1.8 * u, color: c.accent),
              SizedBox(width: 0.5 * u),
              Flexible(child: c.line(t, c.st(1.35, color: c.on(dark), weight: FontWeight.w600))),
            ]),
          ),
      ]),
    ),
  );
  return Container(
    color: Colors.white,
    child: Column(children: [
      Container(
        padding: EdgeInsets.fromLTRB(2.5 * u, 1.6 * u, 2.5 * u, 1.6 * u),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c.primary, Color.lerp(c.primary, c.accent, 0.55)!]),
        ),
        height: c.h * (c.landscape ? 0.36 : 0.26),
        child: strip,
      ),
      Expanded(
        child: Padding(
          padding: EdgeInsets.fromLTRB(3 * u, 1.6 * u, 3 * u, 1.2 * u),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (c.landscape) ...[
              c.logo(11 * u, fallbackBg: c.primary),
              SizedBox(width: 2.4 * u),
            ],
            Expanded(child: Align(alignment: Alignment.centerLeft, child: serviceBlock)),
          ]),
        ),
      ),
      if (contacts.isNotEmpty) bar,
      Row(children: [
        Expanded(flex: 3, child: Container(height: 0.9 * u, color: c.primary)),
        Expanded(flex: 2, child: Container(height: 0.9 * u, color: c.accent)),
      ]),
    ]),
  );
}

// ---------------------------------------------------------------------------
// Verso « Galerie de réalisations » : grille de photos encadrées.
Widget versoGalerie(CardCtx c) {
  final u = c.u;
  final fg = c.on(c.primary);
  final count = c.school.gallery.isEmpty ? 6 : math.min(c.landscape ? 9 : 6, math.max(4, c.school.gallery.length));
  final cols = c.landscape ? (count > 6 ? 3 : (count > 4 ? 3 : 2)) : 2;
  final rows = (count / cols).ceil();
  final grid = c.layer(
    'photo',
    LayoutBuilder(builder: (context, box) {
      final gap = 0.9 * u;
      final cw = (box.maxWidth - gap * (cols - 1)) / cols;
      final ch = (box.maxHeight - gap * (rows - 1)) / rows;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (var i = 0; i < count; i++)
          Container(
            width: cw,
            height: ch,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.white, width: 0.4 * u),
              borderRadius: BorderRadius.circular(0.8 * u),
            ),
            clipBehavior: Clip.antiAlias,
            child: _picture(c, i),
          ),
      ]);
    }),
  );
  final side = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _brand(c, nameColor: c.secondary, sloganColor: c.primary, logo: 8),
    SizedBox(height: 1.2 * u),
    Expanded(
        child: Align(
            alignment: Alignment.centerLeft,
            child: c.layer('info', _services(c, bullet: c.primary, textColor: c.secondary, size: 2.0, max: 7)))),
    for (final (i, t) in [
      if (c.school.phone.isNotEmpty) (Icons.phone_in_talk, c.school.phone),
      if (c.school.website.isNotEmpty) (Icons.language, c.school.website),
    ])
      _iconRow(c, i, t, iconBg: c.primary, iconFg: fg, textColor: c.secondary, size: 1.5),
  ]);
  if (!c.landscape) {
    return Container(
      color: Colors.white,
      child: Column(children: [
        Expanded(
          flex: 5,
          child: Container(color: c.primary, padding: EdgeInsets.all(2 * u), child: grid),
        ),
        Container(height: 0.8 * u, color: c.accent),
        Expanded(flex: 4, child: Padding(padding: EdgeInsets.all(2.5 * u), child: side)),
      ]),
    );
  }
  return Container(
    color: Colors.white,
    child: Row(children: [
      Expanded(flex: 10, child: Padding(padding: EdgeInsets.fromLTRB(2.8 * u, 2.6 * u, 2 * u, 2.2 * u), child: side)),
      Container(width: 0.8 * u, color: c.accent),
      Expanded(
        flex: 11,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.primary, Color.lerp(c.primary, Colors.black, 0.3)!],
            ),
          ),
          padding: EdgeInsets.all(1.8 * u),
          child: grid,
        ),
      ),
    ]),
  );
}

// ---------------------------------------------------------------------------
// Verso « Texte et mentions » : utile aussi pour les cartes scolaires et professionnelles.
Widget versoTexte(CardCtx c) {
  final u = c.u;
  final text = c.resolve(c.t.versoText);
  return Container(
    color: Colors.white,
    child: Column(children: [
      Container(height: 1.4 * u, color: c.primary),
      Container(height: 0.5 * u, color: c.accent),
      Expanded(
        child: Padding(
          padding: EdgeInsets.fromLTRB(4 * u, 2.5 * u, 4 * u, 2 * u),
          child: Column(children: [
            Row(children: [
              c.logo(8 * u),
              SizedBox(width: 1.5 * u),
              Expanded(
                child: c.layer(
                  'header',
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    c.line(c.school.name.toUpperCase(), c.st(2.1, color: c.secondary, weight: FontWeight.w900)),
                    if (c.school.address.isNotEmpty || c.school.phone.isNotEmpty)
                      c.line([c.school.address, c.school.phone].where((e) => e.isNotEmpty).join(' • '),
                          c.st(1.4, color: const Color(0xFF4A5059))),
                  ]),
                  origin: Alignment.centerLeft,
                ),
              ),
            ]),
            SizedBox(height: 1.6 * u),
            Expanded(
              child: c.layer(
                'info',
                c.fit(Text(text,
                    textAlign: TextAlign.center,
                    style: c.st(2.2 * c.t.textScale, color: const Color(0xFF22262B), weight: FontWeight.w500)),
                    align: Alignment.center),
              ),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (c.t.showQr) c.qr(9 * u),
              const Spacer(),
              if (c.t.showSignature)
                c.layer(
                  'footer',
                  Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    Text(c.school.directorTitle, style: c.st(1.5, color: c.secondary, italic: true)),
                    if (c.school.signerName.isNotEmpty)
                      Text(c.school.signerName, style: c.st(1.6, color: c.secondary, weight: FontWeight.w800)),
                  ]),
                  origin: Alignment.bottomRight,
                ),
            ]),
          ]),
        ),
      ),
      Container(height: 1 * u, color: c.primary),
    ]),
  );
}
