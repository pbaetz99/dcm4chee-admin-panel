// Demo-Daten fuer die PACS-Verwaltung: beantwortet jeden Serveraufruf der Seite (Anmeldung, status.json, rechner.json,
// Dienst unter /admin/dienst/, dcm4chee REST) mit erfundenen Eintraegen im Browser und fragt nie nach (confirm = ja).
// Aenderungen wirken bis zum Neuladen. demo/serve.py laedt die Datei vor config.js.
// Fake backend for the demo: patches window.fetch for every endpoint the admin page calls. Nothing leaves the browser.
// ?demo=platte zeigt eine neue leere Platte, ?demo=ohne eine status.json ohne Platten, ?demo=offen klappt im Firewall-Reiter
// alle Karten auf.
(function () {
  const demo = new URLSearchParams(location.search).get('demo') || '';
  const KONTO = 'max.muster@example.org';
  const cfg = () => Object.assign({ aet: 'DCM4CHEE', iocmAet: 'IOCM_QUALITY' }, window.PACS_ADMIN);
  const vor = min => new Date(Date.now() - min * 60e3);
  const iso = min => { const d = vor(min); return new Date(d - d.getTimezoneOffset() * 60e3).toISOString().slice(0, 19); };   // Ortszeit wie der Dienst
  const tag = n => iso(n * 1440).slice(0, 10).replace(/-/g, '');   // JJJJMMTT vor n Tagen
  const json = (daten, status) => new Response(JSON.stringify(daten), { status: status || 200, headers: { 'Content-Type': 'application/json' } });
  const nichts = () => new Response(null, { status: 204 });

  // ------------------------------------------------ Uebersicht und Plattenassistent
  const GB = 1e9, TB = 1e12;
  const platte = (nr, groesse, frei, x) => Object.assign({ name: 'PACS-Data0' + nr, groesse, frei, voll: false, in_liste: false, neue_bilder: '', reihe: 0 }, x);
  const status = { stand: iso(3), prefix: 'PACS-Data', frei_gb: 50, warn_gb: 300, platten: [
    platte(1, 2 * TB, 20 * GB, { voll: true }), platte(2, 2 * TB, 70 * GB, { voll: true }), platte(3, 2 * TB, 10 * GB, { voll: true, in_liste: true }),
    platte(4, 4 * TB, 1.6 * TB, { in_liste: true, neue_bilder: 'danach', reihe: 2 }),
    platte(5, 3 * TB, 400 * GB, { in_liste: true, neue_bilder: 'jetzt', reihe: 1 })],
  neue_platten: { kandidaten: demo === 'platte' ? [{ geraet: '/dev/sdg', groesse: 2199023255552, modell: 'Virtual disk' }] : [],
    name: 'PACS-Data06', vorlage: 'PACS-Data05', schwelle: '10GB' },
  dienste: { arc: true, db: true, ldap: true, ohif: true, 'oauth2-proxy': true } };
  if (demo === 'ohne') status.platten = [];

  // Einrichten laeuft ca. 10 s, die Ausgabe waechst wie beim echten pacs-storage.sh
  const AUSGABE = ['--- Plan', 'Gerät /dev/sdg, 2199 GB: keine Partition, kein Dateisystem, erstes MiB leer', '--- Platte',
    'mkfs.ext4 -m 0 -L PACS-Data06 /dev/sdg', 'eingehängt, Eintrag in /etc/fstab', '--- Sichtbar', 'Archiv-Container sieht die Platte',
    '--- Archiv', 'Speicher PACS-Data06 wie PACS-Data05, Schwelle 10GB', 'hinten an die Schreibliste', 'fertig.'];
  let auftrag = {}, auftragAb = 0;
  function auftragStand() {
    if (!auftrag.laeuft) return auftrag;
    const n = Math.min(Math.floor((Date.now() - auftragAb) / 1000) + 1, AUSGABE.length);
    auftrag.ausgabe = AUSGABE.slice(0, n).join('\n') + '\n';
    if (n === AUSGABE.length) {
      Object.assign(auftrag, { laeuft: false, rc: 0, ende: iso(0) });
      status.platten.push(platte(6, auftrag.groesse, auftrag.groesse * .99, { in_liste: true, neue_bilder: 'danach', reihe: 3 }));
      Object.assign(status.neue_platten, { name: 'PACS-Data07', vorlage: 'PACS-Data06' });
    }
    return auftrag;
  }

  // ------------------------------------------------ Firewall
  const e = (quelle, notiz) => ({ quelle, notiz });
  const pub = (port, ziel, container) => ({ port, ziel, container, ipv6: false });   // wie firewall.py ports_lesen
  const pcs = [];
  for (let i = 1; i <= 58; i++) pcs.push({ name: 'PC' + String(i).padStart(3, '0'), ip: '198.51.100.' + (10 + i) });
  pcs.push({ name: 'WS0301', ip: '203.0.113.21' }, { name: 'WS0302', ip: '203.0.113.22' }, { name: 'WS0399', ip: '192.0.2.200' });
  const fw = {
    konfig: { aktiv: true, schnittstelle: 'eth0', standard: 'gesperrt', ausgeblendet: ['2575 192.0.2.86'],
      geaendert: { wer: KONTO, zeit: iso(180) }, regeln: [
        { port: 80, name: 'Viewer und Verwaltung (http)', modus: 'offen', protokollieren: false, erlaubt: [] },
        { port: 443, name: 'Viewer und Verwaltung', modus: 'offen', protokollieren: false, erlaubt: [] },
        { port: 2575, name: 'HL7', modus: 'gesperrt', protokollieren: false, erlaubt: [e('192.0.2.35', 'KIS')] },
        { port: 5601, name: 'Kibana', modus: 'gesperrt', protokollieren: false, erlaubt: [] },
        { port: 8080, name: 'dcm4chee REST (http)', modus: 'gesperrt', protokollieren: false, erlaubt: [e('192.0.2.40', 'Webportal')] },
        { port: 11112, name: 'DICOM', modus: 'probelauf', protokollieren: false, erlaubt: [
          e('192.0.2.21', 'CT1'), e('192.0.2.22', 'MR1'), e('192.0.2.23', 'DX1'), e('192.0.2.31', 'US1'), e('192.0.2.32', 'US2'),
          e('198.51.100.0/24', '58 Client-PCs: PC001, PC002, PC003 …'), e('192.0.2.36', 'Befundstation')] }] },
    wirksam: true, zaehler_seit: iso(180),
    zaehler: { 11112: { verb: { '192.0.2.21': 412, '192.0.2.22': 230, '198.51.100.0/24': 1893 }, fremd: 3, offen: 0 },
      2575: { verb: { '192.0.2.35': 311 }, fremd: 0 }, 5601: { verb: {}, fremd: 5 }, 8443: { verb: {}, fremd: 0, std: 2 } },
    veroeffentlicht: [pub(80, 8080, 'ohif'), pub(443, 8443, 'ohif'), pub(2575, 2575, 'arc'), pub(5601, 5601, 'kibana'),
      pub(8080, 8080, 'arc'), pub(8443, 8443, 'arc'), pub(11112, 11112, 'arc')],
    versuche: [{ art: 'probe', port: 11112, quelle: '192.0.2.77', anzahl: 3, zuletzt: iso(12) },
      { art: 'sperre', port: 5601, quelle: '192.0.2.86', anzahl: 5, zuletzt: iso(95) },
      { art: 'standard', port: 8443, quelle: '203.0.113.9', anzahl: 2, zuletzt: iso(300) }],
    absender: { dicom: [
      { ae: 'CT1', an: 'DCM4CHEE', ip: '192.0.2.21', anzahl: 412, erst: iso(7200), zuletzt: iso(4) },
      { ae: 'MR1', an: 'DCM4CHEE', ip: '192.0.2.22', anzahl: 230, erst: iso(7000), zuletzt: iso(40) },
      { ae: 'US-MOBIL', an: 'DCM4CHEE', ip: '192.0.2.61', anzahl: 12, erst: iso(3000), zuletzt: iso(170) },
      { ae: 'ARCHIV2', an: 'DCM4CHEE', ip: '192.0.2.201', anzahl: 900, erst: iso(7200), zuletzt: iso(2) }],
    hl7: [{ ip: '192.0.2.35', anzahl: 311, erst: iso(7200), zuletzt: iso(6) }], ohne_ae: [] },
    absender_stand: iso(2), clients: { stand: iso(30), muster: 'PC{001..250},WS{0001..0400}', pcs },
    intern: ['127.0.0.0/8', '192.0.2.192/26', '192.0.2.10/32'],   // Docker-Netz (erfunden) und der Server selbst
    vorschlaege: [{ port: 11112, quelle: '203.0.113.0/24', art: 'clients', notiz: '2 Client-PCs: WS0301, WS0302', anzahl: 0, zuletzt: '' },
      { port: 11112, quelle: '192.0.2.77', art: 'versuch-probe', notiz: '', anzahl: 3, zuletzt: iso(12) },
      { port: 11112, quelle: '192.0.2.61', art: 'dicom', notiz: 'US-MOBIL', anzahl: 12, zuletzt: iso(170) }],
    namen: { '192.0.2.77': 'WS0377', '192.0.2.86': 'WS0086', '203.0.113.9': '' },
    kritisch: { 80: 'Viewer und Verwaltung (http)', 443: 'Viewer und Verwaltung', 11112: 'DICOM', 2575: 'HL7' },
    dienstports: { web: [443, 80], dicom: 11112, hl7: 2575 },
  };

  // ------------------------------------------------ dcm4chee: Studien und Patienten
  const pnw = x => ({ vr: 'PN', Value: [{ Alphabetic: x }] });
  const w = (vr, x) => ({ vr, Value: [x] });
  const wert = (o, t) => ((o[t] || {}).Value || [])[0];
  const studie = (uid, name, pid, datum, acc, mod, beschr, zuw, n) => ({
    '0020000D': w('UI', uid), '00100010': pnw(name), '00100020': w('LO', pid), '00100021': w('LO', 'DEMO'),
    '00080020': w('DA', datum), '00080030': w('TM', '101500'), '00080050': w('SH', acc), '00080061': { vr: 'CS', Value: mod.split('/') },
    '00080090': pnw(zuw), '00081030': w('LO', beschr), '00201208': w('IS', n) });
  let studien = [
    studie('2.25.1001', 'Muster^Maria', '100001', tag(0), 'ACC1001', 'MR', 'MRT Lendenwirbelsäule', 'Hausarzt^Hans', 412),
    studie('2.25.1002', 'Beispiel^Bernd', '100233', tag(0), 'ACC1002', 'CR', 'Thorax pa', 'Beispiel^Lena', 1),
    studie('2.25.1003', 'Test^Theo', '100417', tag(1), 'ACC1003', 'CT/SR', 'CT Schädel nativ', 'Notarzt^Nina', 188),
    studie('2.25.1004', 'Probe^Paula', '100521', tag(1), 'ACC1004', 'US', 'Sono Abdomen', 'Hausarzt^Hans', 24),
    studie('2.25.1006', 'Beispiel^Bernd', '100233', tag(30), 'ACC1006', 'CT', 'CT Thorax', 'Beispiel^Lena', 310),
    studie('2.25.1005', 'Muster^Maria', '100001', tag(200), 'ACC1005', 'DX', 'Knie li in 2 Ebenen', 'Ortho^Otto', 2)];
  let abgelehnt = [studie('2.25.1007', 'Muster^Max', '100777', tag(2), 'ACC1007', 'DX', 'Hand re (falscher Patient)', 'Hausarzt^Hans', 2)];
  const patient = (pid, name, geb, sex) => ({ '00100010': pnw(name), '00100020': w('LO', pid), '00100021': w('LO', 'DEMO'),
    '00100030': w('DA', geb), '00100040': w('CS', sex) });
  let patienten = [patient('100001', 'Muster^Maria', '19510213', 'F'), patient('100233', 'Beispiel^Bernd', '19600101', 'M'),
    patient('100234', 'Beispiel^Bernd', '19600110', 'M'), patient('100417', 'Test^Theo', '19880517', 'M'),
    patient('100521', 'Probe^Paula', '19721130', 'F'), patient('100777', 'Muster^Max', '19900704', 'M')];

  const passt = (x, q) => {
    const name = (q.get('PatientName') || '').replace(/\*$/, '').toLowerCase(), uids = q.get('StudyInstanceUID');
    const [von, bis] = (q.get('StudyDate') || '-').split('-'), d = wert(x, '00080020') || '';
    return (!q.get('PatientID') || wert(x, '00100020') === q.get('PatientID')) &&
      (!name || ((wert(x, '00100010') || {}).Alphabetic || '').toLowerCase().startsWith(name)) &&
      (!q.get('AccessionNumber') || wert(x, '00080050') === q.get('AccessionNumber')) &&
      (!uids || uids.split(',').includes(wert(x, '0020000D'))) && (!von || d >= von) && (!bis || d <= bis);
  };
  const liste = r => (r.length ? json(r) : nichts());   // dcm4chee: 204 = nichts gefunden
  const pidAus = kennung => decodeURIComponent(kennung).split('^^^')[0];
  const umhaengen = (s, p) => { s['00100020'] = p['00100020']; s['00100010'] = p['00100010']; };

  function rest(m, p, q, body) {
    const korb = p.includes('/aets/' + cfg().iocmAet + '/');
    let x;
    if (m === 'GET' && /\/rs\/studies$/.test(p)) return liste((korb ? abgelehnt : studien).filter(s => passt(s, q)));
    if (m === 'GET' && /\/rs\/patients$/.test(p)) {
      return liste(patienten.filter(s => passt(s, q)).map(s => Object.assign({}, s,
        { '00201200': w('IS', studien.filter(t => wert(t, '00100020') === wert(s, '00100020')).length) })));
    }
    if ((x = p.match(/\/rs\/studies\/([^/]+)\/reject\/(.+)$/))) {
      const [aus, nach] = /REVOKE/.test(x[2]) ? [abgelehnt, studien] : [studien, abgelehnt];
      const i = aus.findIndex(s => wert(s, '0020000D') === x[1]);
      if (i >= 0) nach.unshift(...aus.splice(i, 1));
      return json({ count: 1 });
    }
    if (m === 'DELETE' && (x = p.match(/\/rs\/studies\/([^/]+)$/))) { abgelehnt = abgelehnt.filter(s => wert(s, '0020000D') !== x[1]); return nichts(); }
    if (p.endsWith('/rs/studies/update')) {
      Object.assign(studien.find(s => wert(s, '0020000D') === q.get('StudyInstanceUID')) || {}, body);
      return json({});
    }
    if ((x = p.match(/\/rs\/studies\/([^/]+)\/patient$/))) {
      const s = studien.find(t => wert(t, '0020000D') === x[1]), z = patienten.find(t => wert(t, '00100020') === q.get('PatientID'));
      if (s && z) umhaengen(s, z);
      return json({});
    }
    if ((x = p.match(/\/rs\/patients\/([^/]+)\/merge\/([^/]+)$/))) {
      const alt = pidAus(x[1]), z = patienten.find(t => wert(t, '00100020') === pidAus(x[2]));
      studien.filter(s => wert(s, '00100020') === alt).forEach(s => z && umhaengen(s, z));
      patienten = patienten.filter(t => wert(t, '00100020') !== alt);
      return json({});
    }
    if (m === 'PUT' && (x = p.match(/\/rs\/patients\/([^/]+)$/))) {
      const i = patienten.findIndex(t => wert(t, '00100020') === pidAus(x[1]));
      if (i >= 0) patienten[i] = body;
      studien.filter(s => wert(s, '00100020') === pidAus(x[1])).forEach(s => umhaengen(s, body));
      return json({});
    }
    return m === 'GET' ? nichts() : json({});
  }

  // ------------------------------------------------ Protokoll (je Zeile ein JSON wie vom Dienst)
  const rechner = { '198.51.100.27': 'PC017', '198.51.100.34': 'PC024', '198.51.100.45': 'PC035' };
  function protokoll() {
    const rs = '/dcm4chee-arc/aets/' + cfg().aet + '/rs/studies';
    const zugriff = (min, u, ip, r) => ({ t: vor(min).toISOString(), u, sub: 'x', ip, r, status: 200 });
    const admin = (min, uri, k, status, m) => ({ t: vor(min).toISOString(), u: KONTO, sub: 'x', ip: '198.51.100.45', r: 'admin', m: m || 'POST',
      status: status || 200, uri, k: encodeURIComponent(k) });
    return [
      admin(2 * 1440 + 30, '/admin/dienst/freigeben', 'Markierung voll entfernt · PACS-Data03', 409),
      admin(2 * 1440 + 10, '/dcm4chee-arc/aets/' + cfg().aet + '/rs/studies/2.25.1007/reject/113001%5EDCM',
        'Studie abgelehnt · 100777 · Muster, Max · ACC1007 · Hand re (falscher Patient)'),
      zugriff(1440 + 200, 'lena.beispiel@example.org', '198.51.100.34', rs + '?StudyDate=' + tag(1) + '-' + tag(1) + '&limit=101'),
      zugriff(1440 + 198, 'lena.beispiel@example.org', '198.51.100.34', rs + '/2.25.1003/series'),
      admin(180, '/admin/dienst/firewall', 'Firewall geändert · 11112: + 198.51.100.0/24 (58 Client-PCs) · 5601: offen → gesperrt'),
      zugriff(125, 'lena.beispiel@example.org', '198.51.100.34', rs + '?PatientID=100233&limit=101'),
      zugriff(124, 'lena.beispiel@example.org', '198.51.100.34', rs + '/2.25.1002/series'),
      admin(60, '/dcm4chee-arc/aets/' + cfg().aet + '/rs/studies/update?reasonForModification=CORRECT&StudyInstanceUID=2.25.1001',
        'Studie bearbeitet · 100001 · Muster, Maria · Zuweiser Beispiel, Anna → Hausarzt, Hans'),
      zugriff(6, 'anna.beispiel@example.org', '198.51.100.27', rs + '?PatientName=Muster*&limit=101'),
      zugriff(5, 'anna.beispiel@example.org', '198.51.100.27', rs + '/2.25.1001/series'),
      zugriff(4, 'anna.beispiel@example.org', '198.51.100.27', rs + '/2.25.1001/series/2.25.2001/instances/2.25.3001/metadata'),
    ];
  }

  // ------------------------------------------------ fetch ersetzen
  const echt = window.fetch.bind(window);
  window.fetch = async (eingabe, o) => {
    o = o || {};
    const url = new URL(String(eingabe), location.origin), p = url.pathname, q = url.searchParams, m = (o.method || 'GET').toUpperCase();
    let body = null;
    try { body = o.body ? JSON.parse(o.body) : null; } catch (x) { /* kein JSON */ }
    if (p === '/oauth2/userinfo') return json({ preferredUsername: KONTO, email: KONTO });
    if (p === '/admin/daten/status.json') return json(status);
    if (p === '/admin/daten/rechner.json') return json(rechner);
    if (p === '/admin/dienst/auftrag') return json(auftragStand());
    if (p === '/admin/dienst/platten') return json({ ok: true });
    if (p === '/admin/dienst/einrichten' && m === 'POST') {
      auftrag = { laeuft: true, wer: KONTO, geraet: body.geraet, groesse: body.groesse, name: body.name, start: iso(0), ausgabe: '' };
      auftragAb = Date.now();
      status.neue_platten.kandidaten = [];
      return json(auftrag, 202);
    }
    if (/^\/admin\/dienst\/(freigeben|anhaengen|abhaengen)$/.test(p) && m === 'POST') {
      const pl = status.platten.find(x => x.name === body.platte);
      if (pl && p.endsWith('abhaengen')) Object.assign(pl, { in_liste: false, neue_bilder: '', reihe: 0 });
      else if (pl) {
        pl.voll = false;
        if (p.endsWith('anhaengen')) Object.assign(pl, { in_liste: true, neue_bilder: 'danach', reihe: Math.max(...status.platten.map(x => x.reihe)) + 1 });
      }
      // Schreibliste neu durchzaehlen: die erste nimmt jetzt neue Bilder
      status.platten.filter(x => x.neue_bilder).sort((a, b) => a.reihe - b.reihe)
        .forEach((x, i) => Object.assign(x, { reihe: i + 1, neue_bilder: i ? 'danach' : 'jetzt' }));
      return json({ ok: true });
    }
    if (p === '/admin/dienst/protokoll') {
      const quellen = (q.get('quelle') || 'ereignisse,admin').split(',');
      const z = protokoll().filter(x => quellen.includes(x.r === 'admin' ? 'admin' : 'ereignisse'));
      return new Response(z.slice(-(+q.get('letzte') || z.length)).map(x => JSON.stringify(x)).join('\n'),
        { status: 200, headers: { 'Content-Type': 'application/x-ndjson' } });
    }
    if (p === '/admin/dienst/firewall') {
      if (m === 'POST') Object.assign(fw, { konfig: Object.assign(body, { geaendert: { wer: KONTO, zeit: iso(0) } }), zaehler_seit: iso(0) });
      if (q.get('neu')) Object.assign(fw, { absender_stand: iso(0), clients: Object.assign(fw.clients, { stand: iso(0) }) });
      return json(fw);
    }
    if (p.startsWith('/admin/dienst/')) return json({ fehler: 'unbekannt' }, 404);
    if (p.startsWith('/dcm4chee-arc/')) return rest(m, p, q, body);
    return echt(eingabe, o);
  };
  window.confirm = () => true;

  // Studien, Patienten und Protokoll gleich mit Inhalt zeigen (leere Suche = alles)
  const auto = () => setTimeout(() => {
    const f = document.getElementById({ '#studien': 'f-studien', '#patienten': 'f-patienten', '#protokoll': 'p-form' }[location.hash]);
    if (f && !f.dataset.demo) { f.dataset.demo = '1'; f.requestSubmit(); }
    if (demo === 'offen' && location.hash === '#firewall') document.querySelectorAll('#firewall details').forEach(d => (d.open = true));
  }, 300);
  addEventListener('load', auto);
  addEventListener('hashchange', auto);
})();
