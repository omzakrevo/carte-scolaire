# ML Kit : seule la reconnaissance du texte latin est incluse ; les autres langues
# (chinois, devanagari, japonais, coréen) sont référencées par le plugin mais absentes.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ONNX Runtime (détourage des photos, détection du visage) : le code natif appelle ces
# classes Java par leur nom ; R8 ne doit ni les retirer ni les renommer.
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**
