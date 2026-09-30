// Einstellungen der PACS-Verwaltung fuer diesen Standort; index.html laedt die Datei vor dem eigenen Skript.
// Site settings for the admin page. Edit the values below, no other file needs changing.
window.PACS_ADMIN = {
  titel: 'PACS-Verwaltung',             // Seitentitel und Text im Kopf
  aet: 'DCM4CHEE',                      // AE-Titel des Archivs fuer Suche und Aenderungen (/dcm4chee-arc/aets/<aet>/rs)
  iocmAet: 'IOCM_QUALITY',              // AE-Titel der Ansicht mit den abgelehnten Studien (zurueckholen, endgueltig loeschen)
  dcm4cheeUrl: '/dcm4chee-arc/ui2/',    // Verweis "dcm4chee" im Kopf, leer = ausblenden
  viewerUrl: '/',                       // Verweis "Viewer" im Kopf, leer = ausblenden
  logo: '',                             // Logo (hell, fuer dunklen Grund) von derselben Adresse, z. B. '/pacs-logo.svg'
                                        // (docker-compose.example.yml); von einem anderen Server laedt es nicht
                                        // (require-corp). Leer = nur Text
  locale: 'de-DE',                      // Zahlen und Zeitpunkte, z. B. 'de-AT' oder 'de-CH'; DICOM-Datum (Studie,
                                        // Geburt) immer TT.MM.JJJJ; ungueltig = de-DE
};
