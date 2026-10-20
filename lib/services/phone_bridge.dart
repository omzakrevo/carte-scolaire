import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Petit serveur web local : le téléphone ouvre l'adresse affichée (QR code)
/// dans son navigateur, prend la photo avec son appareil et l'envoie
/// directement à l'ordinateur via le Wi-Fi. Aucune application à installer
/// sur le téléphone, aucune connexion Internet requise.
class PhoneBridge {
  final Map<String, dynamic> Function() state;
  final Future<void> Function(Uint8List bytes) onPhoto;
  final void Function(int delta) onNavigate;

  PhoneBridge({required this.state, required this.onPhoto, required this.onNavigate});

  HttpServer? _server;
  final String key = _randomKey();
  int port = 0;

  /// Dernier contact du téléphone (sert à afficher « connecté »).
  final ValueNotifier<DateTime?> lastSeen = ValueNotifier(null);
  final ValueNotifier<int> received = ValueNotifier(0);

  bool get running => _server != null;

  static String _randomKey() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> start() async {
    if (_server != null) return;
    for (var p = 8787; p < 8800; p++) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, p);
        port = p;
        break;
      } on SocketException {
        continue;
      }
    }
    if (_server == null) throw const SocketException('Aucun port disponible (8787-8799)');
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  String urlFor(String ip) => 'http://$ip:$port/?k=$key';

  /// Adresses IPv4 locales de l'ordinateur, réseau Wi-Fi/Ethernet d'abord.
  static Future<List<String>> localIps() async {
    final list = <String>[];
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    for (final i in ifaces) {
      for (final a in i.addresses) {
        if (!a.isLoopback) list.add(a.address);
      }
    }
    int rank(String ip) {
      if (ip.startsWith('192.168.')) return 0;
      if (ip.startsWith('10.')) return 1;
      if (ip.startsWith('172.')) return 2;
      if (ip.startsWith('169.254.')) return 9;
      return 5;
    }

    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.uri.queryParameters['k'] != key) {
        res.statusCode = HttpStatus.forbidden;
        res.write('Lien invalide. Scannez à nouveau le QR code affiché sur l\'ordinateur.');
        await res.close();
        return;
      }
      lastSeen.value = DateTime.now();
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/') {
        res.headers.contentType = ContentType.html;
        res.write(_page);
      } else if (req.method == 'GET' && path == '/state') {
        res.headers.contentType = ContentType.json;
        res.headers.set('Cache-Control', 'no-store');
        res.write(jsonEncode(state()));
      } else if (req.method == 'POST' && path == '/nav') {
        final d = int.tryParse(req.uri.queryParameters['d'] ?? '0') ?? 0;
        onNavigate(d);
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode(state()));
      } else if (req.method == 'POST' && path == '/upload') {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in req) {
          builder.add(chunk);
          if (builder.length > 25 * 1024 * 1024) throw const FormatException('Fichier trop lourd');
        }
        await onPhoto(builder.takeBytes());
        received.value++;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({'ok': true, ...state()}));
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      res.statusCode = HttpStatus.internalServerError;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'ok': false, 'error': e.toString()}));
    }
    await res.close();
  }
}

const _page = r'''<!doctype html>
<html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Photo carte scolaire</title>
<style>
:root{--g:#0b6b3a;--bg:#f3f5f2;--fg:#17201b;--mut:#5f6b64}
*{box-sizing:border-box}body{margin:0;font:16px/1.4 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--fg)}
main{max-width:480px;margin:0 auto;padding:20px 16px 32px;display:flex;flex-direction:column;gap:14px}
h1{font-size:18px;margin:0;color:var(--g)}
.card{background:#fff;border-radius:14px;padding:16px;box-shadow:0 1px 3px rgba(0,0,0,.08)}
.pos{color:var(--mut);font-size:14px}.name{font-size:22px;font-weight:800;margin:4px 0}
.cls{display:inline-block;background:#e6f2ea;color:var(--g);font-weight:700;border-radius:20px;padding:2px 10px;font-size:14px}
.btn{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;border:0;border-radius:12px;padding:16px;font-size:18px;font-weight:700;cursor:pointer}
.pri{background:var(--g);color:#fff}.sec{background:#fff;color:var(--fg);border:1px solid #d5dbd7}
.row{display:flex;gap:10px}.row .btn{font-size:16px;padding:14px}
input[type=file]{display:none}
#msg{min-height:22px;text-align:center;font-weight:600}
#prev{width:100%;border-radius:12px;display:none}
.ok{color:var(--g)}.err{color:#b3261e}
</style></head><body><main>
<h1>Photo de la carte scolaire</h1>
<div class="card"><div class="pos" id="pos">Connexion…</div><div class="name" id="name">—</div><span class="cls" id="cls"></span><div class="pos" id="has"></div></div>
<label class="btn pri">Prendre la photo<input id="cam" type="file" accept="image/*" capture="environment"></label>
<label class="btn sec">Choisir dans la galerie<input id="gal" type="file" accept="image/*"></label>
<img id="prev" alt="">
<div id="msg"></div>
<div class="row"><button class="btn sec" id="p">◀ Précédent</button><button class="btn sec" id="n">Suivant ▶</button></div>
</main>
<script>
const k=new URLSearchParams(location.search).get('k');
const $=id=>document.getElementById(id);
function show(s){if(!s||s.total===0){$('pos').textContent='Aucun élève dans la liste';$('name').textContent='—';$('cls').textContent='';$('has').textContent='';return;}
$('pos').textContent='Élève '+(s.index+1)+' sur '+s.total;$('name').textContent=s.name||'—';$('cls').textContent=s.classe||'';$('cls').style.display=s.classe?'inline-block':'none';
$('has').textContent=s.hasPhoto?'✓ Photo déjà enregistrée':'Pas encore de photo';}
async function poll(){try{const r=await fetch('/state?k='+k,{cache:'no-store'});show(await r.json());}catch(e){$('pos').textContent='Ordinateur injoignable…';}}
setInterval(poll,1500);poll();
async function nav(d){const r=await fetch('/nav?k='+k+'&d='+d,{method:'POST'});show(await r.json());$('prev').style.display='none';$('msg').textContent='';}
$('p').onclick=()=>nav(-1);$('n').onclick=()=>nav(1);
async function shrink(file){try{const bmp=await createImageBitmap(file);const m=1600,s=Math.min(1,m/Math.max(bmp.width,bmp.height));
const c=document.createElement('canvas');c.width=Math.round(bmp.width*s);c.height=Math.round(bmp.height*s);c.getContext('2d').drawImage(bmp,0,0,c.width,c.height);
return await new Promise(r=>c.toBlob(r,'image/jpeg',0.9));}catch(e){return file;}}
async function send(file){if(!file)return;$('msg').className='';$('msg').textContent='Envoi en cours…';
const blob=await shrink(file);$('prev').src=URL.createObjectURL(blob);$('prev').style.display='block';
try{const r=await fetch('/upload?k='+k,{method:'POST',body:blob});const j=await r.json();
if(j.ok){$('msg').className='ok';$('msg').textContent='✓ Photo reçue par l\'ordinateur';show(j);}else{throw new Error(j.error);}}
catch(e){$('msg').className='err';$('msg').textContent='Échec de l\'envoi : '+e.message;}}
$('cam').onchange=e=>{send(e.target.files[0]);e.target.value='';};
$('gal').onchange=e=>{send(e.target.files[0]);e.target.value='';};
</script></body></html>''';
