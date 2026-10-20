import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models.dart';

typedef CardBuilder = Widget Function(CardCtx c);

/// Un modèle de carte : nom, couleurs et format par défaut, dessin.
class CardDesign {
  final String id;
  final String name;
  final String description;
  final int primary;
  final int secondary;
  final int accent;
  final double defaultWidth;
  final double defaultHeight;
  final CardBuilder build;

  const CardDesign({
    required this.id,
    required this.name,
    required this.description,
    required this.primary,
    required this.secondary,
    required this.accent,
    this.defaultWidth = 85.6,
    this.defaultHeight = 54,
    required this.build,
  });
}

CardDesign designById(String id) => cardDesigns.firstWhere((d) => d.id == id, orElse: () => cardDesigns.first);

const cardDesigns = <CardDesign>[
  CardDesign(
    id: 'identite',
    name: 'Identité scolaire',
    description: 'En-tête officiel, titre rouge, vague avec nom et devise de l\'école',
    primary: 0xFFE31E24,
    secondary: 0xFF1B2A6B,
    accent: 0xFFFFF3B0,
    build: _identite,
  ),
  CardDesign(
    id: 'officiel',
    name: 'Officiel tricolore',
    description: 'En-tête pays et ministère, drapeau, bandeau titre',
    primary: 0xFF009E49,
    secondary: 0xFFEF2B2D,
    accent: 0xFFFCD116,
    build: _officiel,
  ),
  CardDesign(
    id: 'bandeau',
    name: 'Classique bandeau',
    description: 'Bandeau dégradé en haut, pied avec année scolaire',
    primary: 0xFF1E4FA1,
    secondary: 0xFF0F2E66,
    accent: 0xFFF2A900,
    build: _bandeau,
  ),
  CardDesign(
    id: 'diagonale',
    name: 'Moderne diagonale',
    description: 'Formes obliques dans les angles',
    primary: 0xFF00897B,
    secondary: 0xFF263238,
    accent: 0xFFFFB300,
    build: _diagonale,
  ),
  CardDesign(
    id: 'vague',
    name: 'Vagues',
    description: 'En-tête ondulé, ton chaleureux',
    primary: 0xFFE65100,
    secondary: 0xFFFFA000,
    accent: 0xFF1565C0,
    build: _vague,
  ),
  CardDesign(
    id: 'badge',
    name: 'Badge vertical',
    description: 'Format portrait, photo ronde, à porter au cou',
    primary: 0xFF8E1B2E,
    secondary: 0xFF2B2B2B,
    accent: 0xFFE0A800,
    defaultWidth: 54,
    defaultHeight: 85.6,
    build: _badge,
  ),
  CardDesign(
    id: 'minimal',
    name: 'Épuré',
    description: 'Barre latérale, beaucoup de blanc',
    primary: 0xFF37474F,
    secondary: 0xFF90A4AE,
    accent: 0xFF26A69A,
    build: _minimal,
  ),
  CardDesign(
    id: 'prestige',
    name: 'Prestige',
    description: 'Fond sombre et filet doré, pour lycées et collèges privés',
    primary: 0xFF0D1B3E,
    secondary: 0xFF1B2D5C,
    accent: 0xFFC9A646,
    build: _prestige,
  ),
  CardDesign(
    id: 'cahier',
    name: 'Cahier d\'écolier',
    description: 'Lignes et marge rouge, idéal pour le primaire',
    primary: 0xFF1A237E,
    secondary: 0xFFE53935,
    accent: 0xFF90CAF9,
    build: _cahier,
  ),
  CardDesign(
    id: 'personnalise',
    name: 'Fond personnalisé',
    description: 'Votre propre fond (Photoshop, Illustrator…) avec photo et infos par-dessus',
    primary: 0xFF1B2A6B,
    secondary: 0xFF1B2A6B,
    accent: 0xFFE31E24,
    build: _personnalise,
  ),
];

/// Aperçu / rendu d'une carte. [scale] = pixels logiques par millimètre.
class CardView extends StatelessWidget {
  final CardTemplate template;
  final SchoolInfo school;
  final Student student;
  final double scale;
  final bool rounded;

  const CardView({
    super.key,
    required this.template,
    required this.school,
    required this.student,
    this.scale = 4,
    this.rounded = true,
  });

  @override
  Widget build(BuildContext context) {
    final w = template.widthMm * scale;
    final h = template.heightMm * scale;
    final c = CardCtx(template, school, student, w, h);
    final design = designById(template.designId);
    return SizedBox(
      width: w,
      height: h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(rounded ? 3 * scale : 0),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: const Color(0xFF1B1F24),
            fontSize: 2 * c.u,
            height: 1.15,
            decoration: TextDecoration.none,
            fontWeight: FontWeight.w400,
          ),
          child: design.build(c),
        ),
      ),
    );
  }
}

/// Contexte de dessin : dimensions, couleurs et briques communes.
class CardCtx {
  final CardTemplate t;
  final SchoolInfo school;
  final Student s;
  final double w;
  final double h;

  /// Unité de dessin : 1/54 du petit côté (≈ 1 mm sur une carte CR80).
  final double u;

  CardCtx(this.t, this.school, this.s, this.w, this.h) : u = math.min(w, h) / 54;

  bool get landscape => w >= h;
  Color get primary => Color(t.primary);
  Color get secondary => Color(t.secondary);
  Color get accent => Color(t.accent);

  Color on(Color c) =>
      ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : const Color(0xFF1B1F24);

  TextStyle st(double size, {Color? color, FontWeight? weight, double? spacing, bool italic = false}) => TextStyle(
        fontSize: size * u,
        color: color,
        fontWeight: weight,
        letterSpacing: spacing == null ? null : spacing * u,
        fontStyle: italic ? FontStyle.italic : null,
        height: 1.15,
      );

  /// Texte sur une ligne qui rétrécit au lieu de déborder.
  Widget line(String text, TextStyle style, {Alignment align = Alignment.centerLeft, TextAlign? textAlign}) =>
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: align,
        child: Text(text, style: style, maxLines: 1, softWrap: false, textAlign: textAlign),
      );

  /// Réduit le contenu s'il dépasse la hauteur disponible.
  Widget fit(Widget child, {Alignment align = Alignment.topLeft}) => LayoutBuilder(
        builder: (context, box) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: align,
          child: SizedBox(width: box.maxWidth, child: child),
        ),
      );

  Widget photo(double pw, double ph, {Color? border, double radius = 0, bool circle = false}) {
    final Widget content = s.photo != null
        ? Image.memory(s.photo!, fit: BoxFit.cover, width: pw, height: ph, gaplessPlayback: true)
        : Container(
            color: const Color(0xFFE4E7EB),
            alignment: Alignment.bottomCenter,
            child: Icon(Icons.person, size: ph * 0.85, color: const Color(0xFFA3ACB6)),
          );
    return Container(
      width: pw,
      height: ph,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border, width: 0.45 * u),
      ),
      child: circle
          ? ClipOval(child: content)
          : ClipRRect(borderRadius: BorderRadius.circular(math.max(0, radius - 0.45 * u)), child: content),
    );
  }

  bool get hasStamp => t.showStamp && school.stamp != null;
  bool get hasSigner => t.showSignature && school.signerName.trim().isNotEmpty;

  /// Photo avec le cachet de l'école posé sur le coin inférieur droit.
  Widget photoWithStamp(double pw, double ph, {Color? border, double radius = 0, bool circle = false}) {
    final p = photo(pw, ph, border: border, radius: radius, circle: circle);
    if (!hasStamp) return p;
    final size = pw * 0.78;
    return Stack(clipBehavior: Clip.none, children: [
      p,
      Positioned(
        right: -size * 0.15,
        bottom: -size * 0.2,
        child: Opacity(
          opacity: 0.85,
          child: Image.memory(school.stamp!, width: size, height: size, fit: BoxFit.contain),
        ),
      ),
    ]);
  }

  Widget logo(double size, {Color? fallbackBg, Color? fallbackFg}) {
    if (school.logo != null) {
      return SizedBox(width: size, height: size, child: Image.memory(school.logo!, fit: BoxFit.contain));
    }
    final bg = fallbackBg ?? primary;
    final words = school.name.split(' ').where((e) => e.isNotEmpty).toList();
    final txt = words.length >= 2 ? words.take(3).map((e) => e[0]).join() : school.shortName;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      padding: EdgeInsets.all(size * 0.14),
      child: FittedBox(
        child: Text(txt.toUpperCase(),
            style: TextStyle(color: fallbackFg ?? on(bg), fontWeight: FontWeight.w800, fontSize: size * 0.4)),
      ),
    );
  }

  /// Emblème / armoiries à droite de l'en-tête (drapeau stylisé par défaut).
  Widget emblem(double size) {
    if (school.emblem != null) {
      return SizedBox(width: size, height: size, child: Image.memory(school.emblem!, fit: BoxFit.contain));
    }
    final fw = size * 0.9;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: fw,
          height: fw * 2 / 3,
          decoration: BoxDecoration(border: Border.all(color: Colors.black12, width: 0.15 * u)),
          child: Stack(children: [
            Column(children: [
              Expanded(child: Container(color: const Color(0xFFEF2B2D))),
              Expanded(child: Container(color: const Color(0xFF009E49))),
            ]),
            Center(child: Icon(Icons.star, color: const Color(0xFFFCD116), size: fw * 0.38)),
          ]),
        ),
      ),
    );
  }

  Widget qr(double size, {Color dark = const Color(0xFF111111)}) => Container(
        width: size,
        height: size,
        color: Colors.white,
        padding: EdgeInsets.all(size * 0.05),
        child: QrImageView(
          data: s.qrData.isEmpty ? '-' : s.qrData,
          padding: EdgeInsets.zero,
          backgroundColor: Colors.white,
          eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: dark),
          dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: dark),
        ),
      );

  String valueOf(String field) => switch (field) {
        'matricule' => s.matricule,
        'nomPrenom' => '${s.nom.toUpperCase()} ${s.prenom}'.trim(),
        'dateNaissance' => s.dateNaissance,
        'lieuNaissance' => s.lieuNaissance,
        'sexe' => s.sexe,
        'classe' => s.classe,
        'contact' => s.contact,
        _ => '',
      };

  /// Champs affichés, dans l'ordre de la carte : (clé, libellé, valeur).
  List<(String, String, String)> fields({bool includeName = true}) => [
        for (final f in cardFields)
          if (t.shows(f) && (includeName || (f != 'nomPrenom' && f != 'classe'))) (f, t.label(f), valueOf(f)),
      ];

  /// Liste « Libellé : valeur », une ligne par champ, réduite si nécessaire.
  Widget info({
    required Color label,
    required Color value,
    bool includeName = true,
    double size = 2.3,
    double labelWidth = 0,
    double spacing = 0.75,
  }) {
    final fs = size * t.textScale;
    final rows = fields(includeName: includeName);
    return fit(Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (key, l, v) in rows)
          Padding(
            padding: EdgeInsets.only(bottom: spacing * u * t.textScale),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '$l : ', style: st(fs * 0.9, color: label, weight: FontWeight.w700)),
                  TextSpan(
                    text: v.isEmpty ? '—' : v,
                    style: st(fs, color: value, weight: key == 'nomPrenom' ? FontWeight.w800 : FontWeight.w500),
                  ),
                ]),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
      ],
    ));
  }

  /// Corps standard paysage : photo (+ cachet, signataire) à gauche, infos, QR.
  Widget bodyLandscape({
    required Color label,
    required Color value,
    Color? photoBorder,
    double photoRadius = 0.8,
    EdgeInsets? padding,
    Color? signerColor,
    Widget? infoTop,
    Widget? bottomRight,
  }) {
    return Padding(
      padding: padding ?? EdgeInsets.fromLTRB(2.4 * u, 1.2 * u, 2.4 * u, 1 * u),
      child: LayoutBuilder(builder: (context, box) {
        final signH = hasSigner ? 2.8 * u : 0.0;
        final maxPh = math.max(10.0, box.maxHeight - signH);
        final ph = math.min(maxPh, maxPh * 0.94 * t.photoScale);
        final pw = math.min(ph * 0.78, box.maxWidth * 0.38);
        final qrSize = math.min(10.5 * u, box.maxHeight * 0.62);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                photoWithStamp(pw, ph, border: photoBorder, radius: photoRadius * u),
                if (hasSigner)
                  SizedBox(
                    width: pw + 2 * u,
                    height: signH,
                    child: Center(
                      child: line(school.signerName, st(1.7, weight: FontWeight.w800, color: signerColor ?? value),
                          align: Alignment.center),
                    ),
                  ),
              ],
            ),
            SizedBox(width: (hasStamp ? 3 : 2) * u),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (infoTop != null) ...[infoTop, SizedBox(height: 0.8 * u)],
                Expanded(child: info(label: label, value: value)),
              ]),
            ),
            if (t.showQr || bottomRight != null) SizedBox(width: 1.2 * u),
            if (t.showQr || bottomRight != null)
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (t.showQr) qr(qrSize) else const SizedBox(),
                  if (bottomRight != null) bottomRight,
                ],
              ),
          ],
        );
      }),
    );
  }

  /// Corps standard portrait : photo en haut, nom en grand, infos dessous.
  Widget bodyPortrait({
    required Color label,
    required Color value,
    required Color nameColor,
    Color? photoBorder,
    bool circle = false,
    Color? pillBg,
    Widget? infoTop,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(3 * u, 1.5 * u, 3 * u, 1 * u),
      child: LayoutBuilder(builder: (context, box) {
        final base = math.min(box.maxHeight * 0.4, box.maxWidth * (circle ? 0.55 : 0.6));
        final ph = base * t.photoScale.clamp(0.7, 1.15);
        final pw = circle ? ph : ph * 0.78;
        return Column(
          children: [
            photoWithStamp(pw, ph, border: photoBorder, radius: 1 * u, circle: circle),
            if (hasSigner)
              line(school.signerName, st(1.6, color: value, weight: FontWeight.w800), align: Alignment.center),
            SizedBox(height: 0.8 * u),
            if (t.shows('nomPrenom')) ...[
              line(s.nom.toUpperCase(), st(3.1 * t.textScale, color: nameColor, weight: FontWeight.w800),
                  align: Alignment.center),
              line(s.prenom, st(2.3 * t.textScale, color: nameColor, weight: FontWeight.w600), align: Alignment.center),
            ],
            SizedBox(height: 0.6 * u),
            if (t.shows('classe') && s.classe.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 2 * u, vertical: 0.4 * u),
                decoration: BoxDecoration(color: pillBg ?? accent, borderRadius: BorderRadius.circular(3 * u)),
                child: Text(s.classe, style: st(2, color: on(pillBg ?? accent), weight: FontWeight.w800)),
              ),
            if (infoTop != null) ...[SizedBox(height: 0.6 * u), infoTop],
            SizedBox(height: 1 * u),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: info(label: label, value: value, includeName: false, size: 2.0)),
                  if (t.showQr) ...[SizedBox(width: 1 * u), qr(math.min(11 * u, box.maxWidth * 0.3))],
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget body({
    required Color label,
    required Color value,
    Color? nameColor,
    Color? photoBorder,
    Color? pillBg,
    bool circle = false,
    Widget? bottomRight,
    Widget? infoTop,
  }) =>
      landscape
          ? bodyLandscape(
              label: label, value: value, photoBorder: photoBorder, bottomRight: bottomRight, infoTop: infoTop)
          : bodyPortrait(
              label: label,
              value: value,
              nameColor: nameColor ?? value,
              photoBorder: photoBorder,
              pillBg: pillBg,
              circle: circle,
              infoTop: infoTop,
            );

  Widget signature(Color color, {CrossAxisAlignment align = CrossAxisAlignment.end}) => !t.showSignature
      ? const SizedBox()
      : Column(
          crossAxisAlignment: align,
          mainAxisSize: MainAxisSize.min,
          children: [Text(school.directorTitle, style: st(1.5, color: color, italic: true))],
        );

  String get year => school.schoolYear.isEmpty ? '' : '${t.yearLabel} ${school.schoolYear}'.trim();

  /// Lignes officielles de l'en-tête (pays, devise, ministère, région).
  List<Widget> officialLines(Color color, {double scale = 1}) => [
        if (school.country.isNotEmpty)
          line(school.country, st(2.3 * scale, color: color, weight: FontWeight.w900), align: Alignment.center),
        if (school.devise.isNotEmpty)
          line(school.devise, st(1.75 * scale, color: color, weight: FontWeight.w800), align: Alignment.center),
        if (school.ministry.isNotEmpty)
          line(school.ministry, st(1.15 * scale, color: color, weight: FontWeight.w700), align: Alignment.center),
        if (school.region.isNotEmpty)
          line(school.region, st(1.15 * scale, color: color, weight: FontWeight.w700), align: Alignment.center),
      ];
}

// ---------------------------------------------------------------------------
// 0. Identité scolaire (en-tête officiel, titre rouge, vague)
class _IdentityWavePainter extends CustomPainter {
  final Color color;
  _IdentityWavePainter(this.color);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final back = Path()
      ..moveTo(w * 0.12, h)
      ..cubicTo(w * 0.4, h * 0.9, w * 0.6, h * 0.74, w, h * 0.6)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(back, Paint()..color = color.withValues(alpha: 0.22));
    final front = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.965)
      ..cubicTo(w * 0.25, h * 0.95, w * 0.45, h * 0.84, w * 0.7, h * 0.77)
      ..cubicTo(w * 0.85, h * 0.73, w * 0.95, h * 0.71, w, h * 0.7)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(front, Paint()..color = color);
    final shine = Path()
      ..moveTo(w * 0.3, h)
      ..cubicTo(w * 0.5, h * 0.9, w * 0.7, h * 0.83, w, h * 0.79);
    canvas.drawPath(
      shine,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.006,
    );
  }

  @override
  bool shouldRepaint(_IdentityWavePainter o) => o.color != color;
}

Widget _identite(CardCtx c) {
  final u = c.u;
  final ink = c.secondary;
  final yearChip = c.year.isEmpty
      ? null
      : Container(
          padding: EdgeInsets.symmetric(horizontal: 1.4 * u, vertical: 0.35 * u),
          color: c.accent,
          child: c.line(c.year, c.st(1.65, color: c.on(c.accent), weight: FontWeight.w900)),
        );
  final titlePill = Container(
    padding: EdgeInsets.symmetric(horizontal: 2.6 * u, vertical: 0.45 * u),
    decoration: BoxDecoration(
      color: c.primary,
      borderRadius: BorderRadius.circular(1.6 * u),
      border: Border.all(color: Colors.white, width: 0.35 * u),
      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 0.8 * u, offset: Offset(0, 0.3 * u))],
    ),
    child: c.line(c.t.title, c.st(c.landscape ? 3.1 : 2.4, color: c.on(c.primary), weight: FontWeight.w900),
        align: Alignment.center),
  );
  final bannerName = c.school.shortName.isNotEmpty ? c.school.shortName : c.school.name;
  final banner = Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
    c.line(bannerName.toUpperCase(),
        c.st(c.landscape ? 3.8 : 3.0, color: Colors.white, weight: FontWeight.w900, spacing: 0.1),
        align: Alignment.centerRight),
    if (c.school.slogan.isNotEmpty)
      c.line(c.school.slogan, c.st(c.landscape ? 1.75 : 1.5, color: Colors.white, weight: FontWeight.w800),
          align: Alignment.centerRight),
  ]);

  final header = Padding(
    padding: EdgeInsets.fromLTRB(1.6 * u, 1 * u, 1.6 * u, 0.4 * u),
    child: Row(children: [
      c.logo(c.landscape ? 12.5 * u : 10 * u),
      SizedBox(width: 1 * u),
      Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: c.officialLines(ink, scale: c.landscape ? 1 : 0.85))),
      SizedBox(width: 1 * u),
      c.emblem(c.landscape ? 11.5 * u : 9 * u),
    ]),
  );

  return Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white, Color(0xFFE3F3FB), Color(0xFFCBE8F6)],
      ),
    ),
    child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _IdentityWavePainter(c.primary))),
      Column(children: [
        header,
        Padding(
          padding: EdgeInsets.symmetric(horizontal: c.w * 0.12),
          child: titlePill,
        ),
        Expanded(
          child: c.landscape
              ? c.bodyLandscape(
                  label: ink,
                  value: const Color(0xFF15171C),
                  photoBorder: ink,
                  photoRadius: 0.3,
                  signerColor: const Color(0xFF15171C),
                  padding: EdgeInsets.fromLTRB(2 * u, 1 * u, 2 * u, 0.2 * u),
                  infoTop: yearChip,
                )
              : c.bodyPortrait(
                  label: ink,
                  value: const Color(0xFF15171C),
                  nameColor: ink,
                  photoBorder: ink,
                  pillBg: c.primary,
                  infoTop: yearChip,
                ),
        ),
        SizedBox(
          height: c.h * (c.landscape ? 0.17 : 0.11),
          child: Padding(
            padding: EdgeInsets.fromLTRB(c.w * 0.38, 0, 2 * u, 0.8 * u),
            child: Align(alignment: Alignment.bottomRight, child: banner),
          ),
        ),
      ]),
    ]),
  );
}

// ---------------------------------------------------------------------------
// Fond personnalisé : image de fond créée dans un logiciel de graphisme.
Widget _personnalise(CardCtx c) {
  final bg = c.t.background;
  return Stack(children: [
    Positioned.fill(
      child: bg != null
          ? Image.memory(bg, fit: BoxFit.cover, gaplessPlayback: true)
          : Container(
              color: const Color(0xFFF2F4F7),
              alignment: Alignment.topCenter,
              padding: EdgeInsets.all(2 * c.u),
              child: c.line(
                  'Ajoutez votre image de fond dans « Modifier le modèle »', c.st(1.6, color: const Color(0xFF7A8490)),
                  align: Alignment.center),
            ),
    ),
    Column(children: [
      SizedBox(height: c.h * c.t.headerSpace.clamp(0.0, 0.6)),
      Expanded(
        child: c.body(
          label: c.secondary,
          value: const Color(0xFF15171C),
          nameColor: c.secondary,
          photoBorder: c.secondary,
          pillBg: c.accent,
          infoTop: c.year.isEmpty ? null : c.line(c.year, c.st(1.6, color: c.accent, weight: FontWeight.w900)),
        ),
      ),
      SizedBox(height: c.h * c.t.footerSpace.clamp(0.0, 0.5)),
    ]),
  ]);
}

// ---------------------------------------------------------------------------
// 1. Officiel tricolore
Widget _officiel(CardCtx c) {
  final u = c.u;
  final header = Padding(
    padding: EdgeInsets.symmetric(horizontal: 2 * u, vertical: 0.8 * u),
    child: Row(children: [
      c.logo(c.landscape ? 8.5 * u : 9 * u),
      SizedBox(width: 1.5 * u),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ...c.officialLines(const Color(0xFF14181D), scale: 0.85),
          c.line(c.school.name.toUpperCase(), c.st(2.1, weight: FontWeight.w800, color: c.primary),
              align: Alignment.center),
        ]),
      ),
      SizedBox(width: 1.5 * u),
      c.emblem(8.5 * u),
    ]),
  );

  return Container(
    color: Colors.white,
    child: Column(children: [
      header,
      Container(height: 0.5 * u, color: c.accent),
      Container(
        height: 3.6 * u,
        color: c.primary,
        alignment: Alignment.center,
        child: Text(c.t.title, style: c.st(2.1, color: c.on(c.primary), weight: FontWeight.w800, spacing: 0.35)),
      ),
      Expanded(
        child: Stack(children: [
          Positioned.fill(
            child: Center(
              child: Opacity(opacity: 0.07, child: Icon(Icons.star, size: c.h * 0.5, color: c.primary)),
            ),
          ),
          c.body(
              label: const Color(0xFF5B6470),
              value: const Color(0xFF14181D),
              nameColor: c.primary,
              photoBorder: c.primary),
        ]),
      ),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 2.4 * u, vertical: 0.4 * u),
        child: Row(children: [
          Expanded(child: c.line(c.year, c.st(1.55, weight: FontWeight.w700, color: c.primary))),
          c.signature(const Color(0xFF5B6470)),
        ]),
      ),
      Row(children: [
        Expanded(child: Container(height: 1 * u, color: c.secondary)),
        Expanded(child: Container(height: 1 * u, color: c.accent)),
        Expanded(child: Container(height: 1 * u, color: c.primary)),
      ]),
    ]),
  );
}

// ---------------------------------------------------------------------------
// 2. Classique bandeau
Widget _bandeau(CardCtx c) {
  final u = c.u;
  final fg = c.on(c.primary);
  return Container(
    color: Colors.white,
    child: Column(children: [
      Container(
        padding: EdgeInsets.symmetric(horizontal: 2.2 * u, vertical: 1.1 * u),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c.primary, c.secondary]),
        ),
        child: Row(children: [
          Container(
            padding: EdgeInsets.all(0.5 * u),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: c.logo(7.5 * u),
          ),
          SizedBox(width: 1.6 * u),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              c.line(c.school.name.toUpperCase(), c.st(2.3, color: fg, weight: FontWeight.w800)),
              c.line([c.school.address, c.school.phone].where((e) => e.isNotEmpty).join(' · '),
                  c.st(1.35, color: fg.withValues(alpha: 0.85))),
              SizedBox(height: 0.4 * u),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 1.2 * u, vertical: 0.2 * u),
                color: c.accent,
                child: c.line(c.t.title, c.st(1.5, color: c.on(c.accent), weight: FontWeight.w800, spacing: 0.2)),
              ),
            ]),
          ),
        ]),
      ),
      Expanded(
        child: c.body(
            label: const Color(0xFF6A7380),
            value: const Color(0xFF141A22),
            nameColor: c.primary,
            photoBorder: c.primary),
      ),
      Container(
        color: c.secondary,
        padding: EdgeInsets.symmetric(horizontal: 2.2 * u, vertical: 0.6 * u),
        child: Row(children: [
          Expanded(child: c.line(c.year, c.st(1.55, color: c.on(c.secondary), weight: FontWeight.w700))),
          c.signature(c.on(c.secondary)),
        ]),
      ),
    ]),
  );
}

// ---------------------------------------------------------------------------
// 3. Moderne diagonale
class _DiagonalPainter extends CustomPainter {
  final Color a, b, accent;
  _DiagonalPainter(this.a, this.b, this.accent);

  @override
  void paint(Canvas canvas, Size s) {
    final top = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width * 0.68, 0)
      ..lineTo(s.width * 0.58, s.height * 0.27)
      ..lineTo(0, s.height * 0.27)
      ..close();
    canvas.drawPath(top, Paint()..color = a);
    final stripe = Path()
      ..moveTo(s.width * 0.70, 0)
      ..lineTo(s.width * 0.73, 0)
      ..lineTo(s.width * 0.63, s.height * 0.27)
      ..lineTo(s.width * 0.60, s.height * 0.27)
      ..close();
    canvas.drawPath(stripe, Paint()..color = accent);
    final bottom = Path()
      ..moveTo(s.width, s.height)
      ..lineTo(s.width * 0.55, s.height)
      ..lineTo(s.width * 0.62, s.height * 0.88)
      ..lineTo(s.width, s.height * 0.88)
      ..close();
    canvas.drawPath(bottom, Paint()..color = b);
  }

  @override
  bool shouldRepaint(_DiagonalPainter o) => o.a != a || o.b != b || o.accent != accent;
}

Widget _diagonale(CardCtx c) {
  final u = c.u;
  final fg = c.on(c.primary);
  return Container(
    color: Colors.white,
    child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _DiagonalPainter(c.primary, c.secondary, c.accent))),
      Column(children: [
        SizedBox(
          height: c.h * 0.27,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 2 * u),
            child: Row(children: [
              c.logo(math.min(c.h * 0.19, c.w * 0.2), fallbackBg: Colors.white, fallbackFg: c.primary),
              SizedBox(width: 1.4 * u),
              SizedBox(
                width: c.w * 0.54 - math.min(c.h * 0.19, c.w * 0.2) - 3.4 * u,
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      c.line(c.school.name.toUpperCase(), c.st(2.1, color: fg, weight: FontWeight.w800)),
                      c.line(c.school.address, c.st(1.3, color: fg.withValues(alpha: 0.9))),
                    ]),
              ),
              const Spacer(),
              SizedBox(
                width: c.w * 0.3,
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      c.line(c.t.title, c.st(1.8, color: c.secondary, weight: FontWeight.w900, spacing: 0.2),
                          align: Alignment.centerRight),
                      c.line(c.school.schoolYear, c.st(1.5, color: c.primary, weight: FontWeight.w700),
                          align: Alignment.centerRight),
                    ]),
              ),
            ]),
          ),
        ),
        Expanded(
          child: c.body(
              label: const Color(0xFF66707A),
              value: const Color(0xFF162026),
              nameColor: c.secondary,
              photoBorder: c.accent),
        ),
        SizedBox(
          height: c.h * 0.12,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 2.4 * u),
            child: Row(children: [
              Expanded(child: c.line(c.school.phone.isEmpty ? '' : 'Tél. ${c.school.phone}', c.st(1.35))),
              SizedBox(
                  width: c.w * 0.45,
                  child: Align(alignment: Alignment.centerRight, child: c.signature(c.on(c.secondary)))),
            ]),
          ),
        ),
      ]),
    ]),
  );
}

// ---------------------------------------------------------------------------
// 4. Vagues
class _WavePainter extends CustomPainter {
  final Color a, b, accent;
  final double headerRatio;
  _WavePainter(this.a, this.b, this.accent, this.headerRatio);

  @override
  void paint(Canvas canvas, Size s) {
    final hh = s.height * headerRatio;
    final back = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, hh * 1.12)
      ..quadraticBezierTo(s.width * 0.75, hh * 0.75, s.width * 0.5, hh * 1.05)
      ..quadraticBezierTo(s.width * 0.25, hh * 1.35, 0, hh * 1.0)
      ..close();
    canvas.drawPath(back, Paint()..color = b);
    final front = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, hh * 0.92)
      ..quadraticBezierTo(s.width * 0.72, hh * 1.18, s.width * 0.45, hh * 0.9)
      ..quadraticBezierTo(s.width * 0.2, hh * 0.65, 0, hh * 0.9)
      ..close();
    canvas.drawPath(front, Paint()..color = a);
    final bottom = Path()
      ..moveTo(0, s.height)
      ..lineTo(0, s.height * 0.95)
      ..quadraticBezierTo(s.width * 0.3, s.height * 0.89, s.width * 0.6, s.height * 0.95)
      ..quadraticBezierTo(s.width * 0.82, s.height * 0.99, s.width, s.height * 0.93)
      ..lineTo(s.width, s.height)
      ..close();
    canvas.drawPath(bottom, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_WavePainter o) => o.a != a || o.b != b || o.accent != accent || o.headerRatio != headerRatio;
}

Widget _vague(CardCtx c) {
  final u = c.u;
  final ratio = c.landscape ? 0.27 : 0.2;
  final fg = c.on(c.primary);
  return Container(
    color: Colors.white,
    child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _WavePainter(c.primary, c.secondary, c.accent, ratio))),
      Column(children: [
        SizedBox(
          height: c.h * ratio * 0.9,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 2.2 * u),
            child: Row(children: [
              c.logo(c.h * ratio * 0.62, fallbackBg: Colors.white, fallbackFg: c.primary),
              SizedBox(width: 1.4 * u),
              Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      c.line(c.school.name.toUpperCase(), c.st(2.2, color: fg, weight: FontWeight.w800)),
                      c.line('${c.t.title}  ·  ${c.school.schoolYear}',
                          c.st(1.45, color: fg, weight: FontWeight.w600, spacing: 0.1)),
                    ]),
              ),
            ]),
          ),
        ),
        SizedBox(height: c.h * ratio * 0.18),
        Expanded(
          child: c.body(
              label: const Color(0xFF7A6A60),
              value: const Color(0xFF231A15),
              nameColor: c.primary,
              photoBorder: c.primary),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(2.4 * u, 0, 2.4 * u, c.h * 0.075),
          child: Row(children: [
            Expanded(
                child: c.line(c.school.phone.isEmpty ? '' : 'Tél. ${c.school.phone}',
                    c.st(1.35, color: const Color(0xFF7A6A60)))),
            c.signature(const Color(0xFF7A6A60)),
          ]),
        ),
      ]),
    ]),
  );
}

// ---------------------------------------------------------------------------
// 5. Badge vertical
class _ArcPainter extends CustomPainter {
  final Color color;
  final double ratio;
  _ArcPainter(this.color, this.ratio);

  @override
  void paint(Canvas canvas, Size s) {
    final hh = s.height * ratio;
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, hh * 0.78)
      ..quadraticBezierTo(s.width / 2, hh * 1.25, 0, hh * 0.78)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArcPainter o) => o.color != color || o.ratio != ratio;
}

Widget _badge(CardCtx c) {
  final u = c.u;
  final fg = c.on(c.primary);
  if (c.landscape) {
    // En paysage, le badge garde son arc mais avec le corps standard.
    return Container(
      color: Colors.white,
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _ArcPainter(c.primary, 0.25))),
        Column(children: [
          SizedBox(
            height: c.h * 0.26,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 2.2 * u),
              child: Row(children: [
                c.logo(c.h * 0.18, fallbackBg: Colors.white, fallbackFg: c.primary),
                SizedBox(width: 1.4 * u),
                Expanded(
                    flex: 3, child: c.line(c.school.name.toUpperCase(), c.st(2.2, color: fg, weight: FontWeight.w800))),
                SizedBox(width: 2 * u),
                Flexible(
                    child: c.line(c.t.title, c.st(1.6, color: c.accent, weight: FontWeight.w800),
                        align: Alignment.centerRight)),
              ]),
            ),
          ),
          Expanded(
              child: c.body(label: const Color(0xFF6B6266), value: const Color(0xFF1E1A1B), photoBorder: c.primary)),
          Container(
            color: c.secondary,
            padding: EdgeInsets.symmetric(horizontal: 2.2 * u, vertical: 0.5 * u),
            child: Row(children: [
              Expanded(child: c.line(c.year, c.st(1.5, color: c.on(c.secondary), weight: FontWeight.w700))),
              c.signature(c.on(c.secondary)),
            ]),
          ),
        ]),
      ]),
    );
  }

  const ratio = 0.30;
  final photoSize = c.w * 0.5;
  return Container(
    color: Colors.white,
    child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _ArcPainter(c.primary, ratio))),
      Column(children: [
        // Trou de lanière
        SizedBox(height: 1.8 * u),
        Container(
          width: 9 * u,
          height: 1.6 * u,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1 * u)),
        ),
        SizedBox(height: 1.2 * u),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 3 * u),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            c.logo(6.5 * u, fallbackBg: Colors.white, fallbackFg: c.primary),
            SizedBox(width: 1.2 * u),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                c.line(c.school.name.toUpperCase(), c.st(1.9, color: fg, weight: FontWeight.w800)),
                c.line(c.t.title, c.st(1.4, color: c.accent, weight: FontWeight.w800, spacing: 0.15)),
              ]),
            ),
          ]),
        ),
        SizedBox(height: math.max(0.0, c.h * ratio - 13 * u - photoSize * 0.45)),
        c.photoWithStamp(photoSize * c.t.photoScale.clamp(0.7, 1.1), photoSize * c.t.photoScale.clamp(0.7, 1.1),
            circle: true, border: Colors.white),
        if (c.hasSigner) c.line(c.school.signerName, c.st(1.6, weight: FontWeight.w800), align: Alignment.center),
        SizedBox(height: 1 * u),
        if (c.t.shows('nomPrenom')) ...[
          c.line(c.s.nom.toUpperCase(), c.st(3.3 * c.t.textScale, color: c.primary, weight: FontWeight.w900),
              align: Alignment.center),
          c.line(c.s.prenom, c.st(2.4 * c.t.textScale, weight: FontWeight.w600), align: Alignment.center),
        ],
        SizedBox(height: 0.8 * u),
        if (c.t.shows('classe') && c.s.classe.isNotEmpty)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 2.4 * u, vertical: 0.4 * u),
            decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(3 * u)),
            child: Text(c.s.classe, style: c.st(2, color: c.on(c.accent), weight: FontWeight.w800)),
          ),
        SizedBox(height: 1.2 * u),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 3 * u),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(children: [
                  Expanded(
                    child: c.info(
                        label: const Color(0xFF6B6266),
                        value: const Color(0xFF1E1A1B),
                        includeName: false,
                        size: 1.85,
                        labelWidth: 9.5),
                  ),
                ]),
              ),
              if (c.t.showQr) ...[SizedBox(width: 1 * u), c.qr(11 * u)],
            ]),
          ),
        ),
        SizedBox(height: 0.8 * u),
        Container(
          width: double.infinity,
          color: c.secondary,
          padding: EdgeInsets.symmetric(horizontal: 2.4 * u, vertical: 0.7 * u),
          child: Row(children: [
            Expanded(child: c.line(c.school.schoolYear, c.st(1.6, color: c.on(c.secondary), weight: FontWeight.w700))),
            c.signature(c.on(c.secondary)),
          ]),
        ),
      ]),
    ]),
  );
}

// ---------------------------------------------------------------------------
// 6. Épuré
Widget _minimal(CardCtx c) {
  final u = c.u;
  const grey = Color(0xFF7B868C);
  return Container(
    color: Colors.white,
    child: Row(children: [
      Container(
        width: 5 * u,
        color: c.primary,
        alignment: Alignment.center,
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(c.t.title, style: c.st(1.7, color: c.on(c.primary), weight: FontWeight.w800, spacing: 0.4)),
        ),
      ),
      Expanded(
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(2.4 * u, 1.6 * u, 2.4 * u, 0.6 * u),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  c.line(c.school.name, c.st(2.2, color: c.primary, weight: FontWeight.w800)),
                  c.line(c.year, c.st(1.4, color: grey)),
                ]),
              ),
              c.logo(6.5 * u),
            ]),
          ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 2.4 * u),
            height: 0.3 * u,
            color: c.accent,
          ),
          Expanded(
            child: c.body(label: grey, value: const Color(0xFF1D2428), nameColor: c.primary, pillBg: c.accent),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(2.4 * u, 0, 2.4 * u, 1 * u),
            child: Row(children: [
              Expanded(
                child: c.line(
                    [c.school.address, c.school.phone].where((e) => e.isNotEmpty).join(' · '), c.st(1.3, color: grey)),
              ),
              c.signature(grey),
            ]),
          ),
        ]),
      ),
    ]),
  );
}

// ---------------------------------------------------------------------------
// 7. Prestige
Widget _prestige(CardCtx c) {
  final u = c.u;
  final gold = c.accent;
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [c.primary, c.secondary],
      ),
    ),
    padding: EdgeInsets.all(1.3 * u),
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: gold, width: 0.3 * u),
        borderRadius: BorderRadius.circular(1.6 * u),
      ),
      child: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(2 * u, 1 * u, 2 * u, 0.4 * u),
          child: Row(children: [
            c.logo(7.5 * u, fallbackBg: gold, fallbackFg: c.primary),
            SizedBox(width: 1.4 * u),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                c.line(
                    c.school.name.toUpperCase(), c.st(2.2, color: Colors.white, weight: FontWeight.w800, spacing: 0.1)),
                c.line(c.t.title, c.st(1.55, color: gold, weight: FontWeight.w700, spacing: 0.35)),
              ]),
            ),
          ]),
        ),
        Container(height: 0.2 * u, margin: EdgeInsets.symmetric(horizontal: 2 * u), color: gold.withValues(alpha: 0.6)),
        Expanded(
          child: c.body(
              label: gold.withValues(alpha: 0.9),
              value: Colors.white,
              nameColor: Colors.white,
              photoBorder: gold,
              pillBg: gold),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(2 * u, 0, 2 * u, 0.8 * u),
          child: Row(children: [
            Expanded(child: c.line(c.year, c.st(1.45, color: gold, weight: FontWeight.w700))),
            c.signature(gold),
          ]),
        ),
      ]),
    ),
  );
}

// ---------------------------------------------------------------------------
// 8. Cahier d'écolier
class _NotebookPainter extends CustomPainter {
  final Color line, margin;
  final double step, marginX;
  _NotebookPainter(this.line, this.margin, this.step, this.marginX);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = line.withValues(alpha: 0.55)
      ..strokeWidth = step * 0.06;
    for (double y = step * 2.2; y < s.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
    final m = Paint()
      ..color = margin.withValues(alpha: 0.7)
      ..strokeWidth = step * 0.1;
    canvas.drawLine(Offset(marginX, 0), Offset(marginX, s.height), m);
  }

  @override
  bool shouldRepaint(_NotebookPainter o) => o.line != line || o.margin != margin || o.step != step;
}

Widget _cahier(CardCtx c) {
  final u = c.u;
  return Container(
    color: const Color(0xFFFFFEF6),
    child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _NotebookPainter(c.accent, c.secondary, 3.4 * u, 4 * u))),
      Padding(
        padding: EdgeInsets.only(left: 4.6 * u),
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(1.6 * u, 1.2 * u, 2.2 * u, 0.4 * u),
            child: Row(children: [
              c.logo(7 * u),
              SizedBox(width: 1.4 * u),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  c.line(c.school.name, c.st(2.3, color: c.primary, weight: FontWeight.w800, italic: true)),
                  Container(
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.secondary, width: 0.3 * u))),
                    child:
                        Text(c.t.title, style: c.st(1.6, color: c.secondary, weight: FontWeight.w800, spacing: 0.25)),
                  ),
                ]),
              ),
              Text(c.school.schoolYear, style: c.st(1.5, color: c.primary, weight: FontWeight.w700)),
            ]),
          ),
          Expanded(
            child: c.body(
                label: const Color(0xFF5C6370),
                value: c.primary,
                nameColor: c.primary,
                photoBorder: c.primary,
                pillBg: c.secondary),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(1.6 * u, 0, 2.2 * u, 0.8 * u),
            child: Row(children: [
              Expanded(
                  child: c.line(c.school.phone.isEmpty ? '' : 'Tél. ${c.school.phone}',
                      c.st(1.3, color: const Color(0xFF5C6370)))),
              c.signature(const Color(0xFF5C6370)),
            ]),
          ),
        ]),
      ),
    ]),
  );
}
