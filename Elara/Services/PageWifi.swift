import Foundation

/// Page web servie à l'ordinateur pour le transfert Wi‑Fi.
enum PageWifi {
    static let html = #"""
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Elara · Transfert Wi‑Fi</title>
<style>
  :root { --violet:#7360f5; --bleu:#388cfa; --fond:#f5f5fa; --carte:#fff; --texte:#1c1c28; --gris:#6b6b80; }
  @media (prefers-color-scheme: dark) { :root { --fond:#111118; --carte:#1d1d28; --texte:#f2f2f7; --gris:#a0a0b4; } }
  * { box-sizing: border-box; }
  body { margin:0; font-family:-apple-system, Segoe UI, Roboto, sans-serif; background:var(--fond); color:var(--texte); }
  header { background:linear-gradient(135deg,#8f66fa,var(--bleu)); color:#fff; padding:28px 16px; text-align:center; }
  header h1 { margin:0; font-size:28px; }
  header p { margin:6px 0 0; opacity:.9; }
  main { max-width:860px; margin:0 auto; padding:16px; }
  .carte { background:var(--carte); border-radius:16px; padding:20px; margin-bottom:16px; box-shadow:0 2px 10px rgba(0,0,0,.06); }
  #zone { border:2px dashed var(--violet); border-radius:14px; padding:36px 16px; text-align:center; cursor:pointer; }
  #zone.survol { background:rgba(115,96,245,.08); }
  .bouton { display:inline-block; margin-top:12px; background:var(--violet); color:#fff; border:0; border-radius:10px; padding:10px 18px; font-size:15px; cursor:pointer; }
  .envoi { margin-top:12px; font-size:14px; }
  .barre { height:6px; background:rgba(127,127,127,.2); border-radius:3px; overflow:hidden; margin-top:4px; }
  .barre > div { height:100%; width:0; background:linear-gradient(90deg,#8f66fa,var(--bleu)); }
  table { width:100%; border-collapse:collapse; font-size:14px; }
  td { padding:10px 6px; border-bottom:1px solid rgba(127,127,127,.18); }
  td.droite { text-align:right; white-space:nowrap; }
  a { color:var(--violet); text-decoration:none; font-weight:600; }
  .gris { color:var(--gris); }
</style>
</head>
<body>
<header>
  <h1>Elara</h1>
  <p>Transfert Wi‑Fi · Wi‑Fi transfer · Передача по Wi‑Fi</p>
</header>
<main>
  <div class="carte">
    <div id="zone">
      <strong>Glissez vos vidéos et musiques ici</strong><br>
      <span class="gris">Drop videos and music here · Перетащите файлы сюда</span><br>
      <button class="bouton" type="button">Choisir des fichiers / Choose files</button>
      <input id="choix" type="file" multiple accept="video/*,audio/*,.mp4,.mov,.m4v,.3gp,.mp3,.m4a,.aac,.wav,.aif,.aiff,.caf,.flac" hidden>
    </div>
    <div id="envois"></div>
  </div>
  <div class="carte">
    <h3 style="margin-top:0">Sur l'iPhone · On the iPhone · На iPhone</h3>
    <table><tbody id="liste"><tr><td class="gris">…</td></tr></tbody></table>
  </div>
  <p class="gris" style="text-align:center;font-size:13px">Gardez Elara ouverte pendant le transfert · Keep Elara open · Не закрывайте Elara</p>
</main>
<script>
  const zone = document.getElementById('zone');
  const choix = document.getElementById('choix');
  zone.addEventListener('click', () => choix.click());
  choix.addEventListener('change', () => envoyer([...choix.files]));
  zone.addEventListener('dragover', e => { e.preventDefault(); zone.classList.add('survol'); });
  zone.addEventListener('dragleave', () => zone.classList.remove('survol'));
  zone.addEventListener('drop', e => { e.preventDefault(); zone.classList.remove('survol'); envoyer([...e.dataTransfer.files]); });

  function ligneEnvoi(nom) {
    const div = document.createElement('div');
    div.className = 'envoi';
    const titre = document.createElement('div');
    titre.textContent = nom;
    const barre = document.createElement('div');
    barre.className = 'barre';
    const plein = document.createElement('div');
    barre.appendChild(plein);
    div.appendChild(titre);
    div.appendChild(barre);
    document.getElementById('envois').appendChild(div);
    return { titre, plein };
  }

  async function envoyer(fichiers) {
    for (const f of fichiers) {
      const l = ligneEnvoi(f.name);
      await new Promise(resolve => {
        const x = new XMLHttpRequest();
        x.open('PUT', '/envoi?nom=' + encodeURIComponent(f.name));
        x.upload.onprogress = e => { if (e.lengthComputable) l.plein.style.width = (e.loaded / e.total * 100) + '%'; };
        x.onload = () => { l.titre.textContent = (x.status === 200 ? '✓ ' : '✗ ') + f.name; l.plein.style.width = '100%'; resolve(); };
        x.onerror = () => { l.titre.textContent = '✗ ' + f.name; resolve(); };
        x.send(f);
      });
      charger();
    }
    choix.value = '';
  }

  async function charger() {
    try {
      const r = await fetch('/liste', { cache: 'no-store' });
      const medias = await r.json();
      const corps = document.getElementById('liste');
      corps.innerHTML = '';
      if (medias.length === 0) {
        corps.innerHTML = '<tr><td class="gris">Aucun média · No media · Нет файлов</td></tr>';
        return;
      }
      for (const m of medias) {
        const tr = document.createElement('tr');
        const nom = document.createElement('td');
        nom.textContent = (m.type === 'audio' ? '♪ ' : '▶ ') + m.nom;
        const infos = document.createElement('td');
        infos.className = 'droite gris';
        infos.textContent = m.duree + ' · ' + m.taille;
        const lien = document.createElement('td');
        lien.className = 'droite';
        const a = document.createElement('a');
        a.href = '/fichier/' + m.id;
        a.textContent = '⬇';
        lien.appendChild(a);
        tr.appendChild(nom); tr.appendChild(infos); tr.appendChild(lien);
        corps.appendChild(tr);
      }
    } catch (e) {}
  }
  charger();
</script>
</body>
</html>
"""#
}
