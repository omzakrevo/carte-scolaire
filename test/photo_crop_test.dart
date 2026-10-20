import 'dart:typed_data';

import 'package:carte_scolaire/screens/photo_crop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('le cadrage démarre centré et couvre le cadre 3:4', (tester) async {
    final orig = Uint8List.fromList(img.encodeJpg(img.Image(width: 1200, height: 800)));
    await tester.pumpWidget(MaterialApp(home: PhotoCropScreen(original: orig)));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    final viewport = tester.getSize(find.byType(InteractiveViewer));
    final child = tester.getSize(find.descendant(of: find.byType(InteractiveViewer), matching: find.byType(SizedBox)).first);
    expect(child.height, moreOrLessEquals(viewport.height, epsilon: 0.5));
    final m = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!.value;
    expect(m.storage[12], moreOrLessEquals(-(child.width - viewport.width) / 2, epsilon: 0.5));
  });
}
