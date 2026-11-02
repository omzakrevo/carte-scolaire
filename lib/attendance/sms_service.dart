import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Envoi de SMS par la puce du téléphone Android (SmsManager), sans intervention.
/// Sur Windows ou iPhone, l'envoi automatique est impossible : on propose WhatsApp.
class SmsService {
  static const _ch = MethodChannel('carte_scolaire/sms');

  static bool get supported => Platform.isAndroid;

  static Future<bool> hasPermission() async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Envoie un SMS. Lève une [SmsException] avec un message clair en cas d'échec.
  static Future<void> send(String to, String text) async {
    if (!supported) throw const SmsException('Envoi de SMS possible uniquement depuis un téléphone Android.');
    try {
      await _ch.invokeMethod('send', {'to': to, 'text': text});
    } on PlatformException catch (e) {
      throw SmsException(switch (e.code) {
        'permission' => 'Autorisation SMS refusée. Autorisez les SMS dans les réglages de l\'application.',
        _ => e.message ?? 'Échec de l\'envoi',
      });
    }
  }

  /// Ouvre WhatsApp avec le message prêt (secours sur ordinateur).
  static Future<bool> openWhatsApp(String to, String text) {
    final n = to.replaceAll(RegExp(r'[^\d]'), '');
    return launchUrl(Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication);
  }
}

class SmsException implements Exception {
  final String message;
  const SmsException(this.message);
  @override
  String toString() => message;
}
