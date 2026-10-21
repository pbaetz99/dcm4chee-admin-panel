#!/usr/bin/env python3
# Encrypted audit log store for the admin panel (SQLCipher via ctypes), stdlib only, Python 3.7+.
# Library: package libsqlcipher1 (Debian 13, SQLCipher 4.x) or libsqlcipher0 (Debian 12 and older, SQLCipher 3.x).
#   PROTOKOLL_DB   Default /var/lib/pacs-protokoll/protokoll.db. Table protokoll: sources zugriffe, ereignisse, admin,
#                  one JSON line per row as nginx sends it by syslog (verwaltung-dienst.py stores it)
#   PROTOKOLL_KEY  Default /etc/pacs-protokoll.key. 64 lowercase hex characters, readable by root only, e.g.
#                  (umask 077; openssl rand -hex 32 > /etc/pacs-protokoll.key). Keep a copy in a password vault:
#                  without the key the database cannot be read any more.
# File format: new files get the SQLCipher 3 format (PRAGMA cipher_compatibility = 3), which libsqlcipher 3.x and 4.x
# both open. A file in the SQLCipher 4 format (created with the 4.x default, e.g. by an older version of this script on
# Debian 13) is found by a second try with the library default. libsqlcipher 3.x cannot open such a file: read it on a
# host with libsqlcipher 4.x (docs/install.de.md#audit-key).
# Read as root: pacsdb.py protokoll SOURCE [FROM [TO]]  |  pacsdb.py test (self-test, does not touch the key file)
# By hand: sqlcipher FILE, then PRAGMA key = "x'<key>'"; (and PRAGMA cipher_compatibility = 3; for a version 3 file)
import ctypes, ctypes.util, datetime, json, os, re, sys, time

DB = os.environ.get("PROTOKOLL_DB") or "/var/lib/pacs-protokoll/protokoll.db"
SCHLUESSEL = os.environ.get("PROTOKOLL_KEY") or "/etc/pacs-protokoll.key"
SCHEMA = [
    "PRAGMA journal_mode = WAL",
    "create table if not exists protokoll (id integer primary key, quelle text not null, zeit real not null, zeile text not null)",
    "create index if not exists protokoll_zeit on protokoll (quelle, zeit)",
]


def _bibliothek():
    for name in (ctypes.util.find_library("sqlcipher"), "libsqlcipher.so.1", "libsqlcipher.so.0", "libsqlcipher.so"):
        if name:
            try:
                return ctypes.CDLL(name)
            except OSError:
                pass
    raise ImportError("libsqlcipher nicht gefunden. Debian 13: apt install libsqlcipher1, Debian 12 und aelter: apt install "
                      "libsqlcipher0 (Release: cat /etc/os-release, Paketname: apt-cache search sqlcipher; docs/install.de.md#audit-key). "
                      "SQLCipher library not found: install libsqlcipher1 (Debian 13) or libsqlcipher0 (Debian 12 and older)")


try:
    _l = _bibliothek()
except ImportError as _e:
    if __name__ == "__main__":   # von Hand aufgerufen: eine Zeile statt Traceback (als Modul bleibt es ein ImportError)
        sys.exit("pacsdb.py: %s" % _e)
    raise
_p, _i = ctypes.c_void_p, ctypes.c_int
for f, arg, res in [
        ("sqlite3_open_v2", [ctypes.c_char_p, ctypes.POINTER(_p), _i, ctypes.c_char_p], _i),
        ("sqlite3_prepare_v2", [_p, ctypes.c_char_p, _i, ctypes.POINTER(_p), _p], _i),
        ("sqlite3_bind_text", [_p, _i, ctypes.c_char_p, _i, _p], _i),
        ("sqlite3_bind_double", [_p, _i, ctypes.c_double], _i),
        ("sqlite3_bind_int64", [_p, _i, ctypes.c_int64], _i),
        ("sqlite3_bind_null", [_p, _i], _i),
        ("sqlite3_step", [_p], _i), ("sqlite3_reset", [_p], _i), ("sqlite3_finalize", [_p], _i),
        ("sqlite3_column_count", [_p], _i), ("sqlite3_column_type", [_p, _i], _i),
        ("sqlite3_column_int64", [_p, _i], ctypes.c_int64), ("sqlite3_column_double", [_p, _i], ctypes.c_double),
        ("sqlite3_column_blob", [_p, _i], _p), ("sqlite3_column_bytes", [_p, _i], _i),
        ("sqlite3_errmsg", [_p], ctypes.c_char_p), ("sqlite3_busy_timeout", [_p, _i], _i), ("sqlite3_close", [_p], _i)]:
    getattr(_l, f).argtypes, getattr(_l, f).restype = arg, res
KOPIEREN = _p(-1)   # SQLITE_TRANSIENT: SQLite kopiert den gebundenen Wert


class Db:
    # versuche: womit die Datei geoeffnet wird, der Reihe nach. 3 = PRAGMA cipher_compatibility = 3 (Format von
    # SQLCipher 3, neue Dateien bekommen es), None = Standard der Bibliothek (4.x: Format 4). Nur der Selbsttest aendert es.
    def __init__(self, pfad=DB, schluessel=SCHLUESSEL, versuche=(3, None)):
        with open(schluessel) as f:
            k = f.read().strip()
        if not re.fullmatch(r"[0-9a-f]{64}", k):
            raise ValueError("Schluessel in %s ist nicht 64 Hex-Zeichen (kleingeschrieben)" % schluessel)
        neu = not os.path.exists(pfad)
        if neu:
            os.makedirs(os.path.dirname(os.path.abspath(pfad)), mode=0o700, exist_ok=True)
        for i, kompat in enumerate(versuche):
            self.h = _p()
            if _l.sqlite3_open_v2(pfad.encode(), ctypes.byref(self.h), 0x2 | 0x4 | 0x10000, None):   # RW, CREATE, FULLMUTEX
                fehler = self._fehler()
                _l.sqlite3_close(self.h)
                raise RuntimeError("%s: %s" % (pfad, fehler))
            if neu:
                os.chmod(pfad, 0o600)
                neu = False
            try:
                _l.sqlite3_busy_timeout(self.h, 15000)
                self.ausfuehren("PRAGMA key = \"x'%s'\"" % k)   # Rohschluessel, keine Ableitung
                # 4.x schreibt sonst bei jedem Fehlversuch ERROR-Zeilen auf stderr. Erst nach key: davor setzt die
                # erste Verbindung des Prozesses den Wert beim Start der Bibliothek wieder zurueck
                self.ausfuehren("PRAGMA cipher_log_level = NONE")
                if kompat:   # 3.x kennt das Pragma nicht und ignoriert es: Format 3 ist dort der Standard
                    self.ausfuehren("PRAGMA cipher_compatibility = %d" % kompat)
                for s in SCHEMA:   # prueft zugleich den Schluessel: falsch = "file is encrypted or is not a database"
                    self.ausfuehren(s)
                self.kompat = kompat
                return
            except RuntimeError as e:
                _l.sqlite3_close(self.h)
                if "not a database" not in str(e) and "encrypted" not in str(e):
                    raise   # z. B. gesperrt: kein Formatproblem
                if i == len(versuche) - 1:
                    raise RuntimeError("%s: %s. Schluessel falsch, keine SQLCipher-Datei oder eine Datei im Format von SQLCipher 4, "
                                       "die libsqlcipher 3.x nicht oeffnet (hier SQLCipher %s), siehe docs/install.de.md#audit-key"
                                       % (pfad, e, _version()))

    def _fehler(self):
        return (_l.sqlite3_errmsg(self.h) or b"").decode("utf-8", "replace")

    def _befehl(self, sql):
        st = _p()
        if _l.sqlite3_prepare_v2(self.h, sql.encode(), -1, ctypes.byref(st), None):
            raise RuntimeError(self._fehler())
        return st

    def _binden(self, st, werte):
        for n, w in enumerate(werte, 1):
            if w is None:
                _l.sqlite3_bind_null(st, n)
            elif isinstance(w, int):
                _l.sqlite3_bind_int64(st, n, w)
            elif isinstance(w, float):
                _l.sqlite3_bind_double(st, n, w)
            else:
                b = str(w).encode("utf-8")
                _l.sqlite3_bind_text(st, n, b, len(b), KOPIEREN)

    def _schritt(self, st):
        rc = _l.sqlite3_step(st)
        if rc not in (100, 101):   # SQLITE_ROW, SQLITE_DONE
            raise RuntimeError(self._fehler())
        return rc == 100

    def abfrage(self, sql, werte=()):
        st = self._befehl(sql)
        try:
            self._binden(st, werte)
            zeilen = []
            while self._schritt(st):
                z = []
                for c in range(_l.sqlite3_column_count(st)):
                    t = _l.sqlite3_column_type(st, c)
                    z.append(_l.sqlite3_column_int64(st, c) if t == 1 else _l.sqlite3_column_double(st, c) if t == 2
                             else None if t == 5 else ctypes.string_at(_l.sqlite3_column_blob(st, c),
                                                                       _l.sqlite3_column_bytes(st, c)).decode("utf-8", "replace"))
                zeilen.append(tuple(z))
            return zeilen
        finally:
            _l.sqlite3_finalize(st)

    def ausfuehren(self, sql, werte=()):
        self.abfrage(sql, werte)

    def viele(self, sql, zeilen):
        # alle Zeilen in einer Transaktion
        self.ausfuehren("begin immediate")
        st = self._befehl(sql)
        try:
            for werte in zeilen:
                self._binden(st, werte)
                self._schritt(st)
                _l.sqlite3_reset(st)
            self.ausfuehren("commit")
        except Exception:
            self.ausfuehren("rollback")
            raise
        finally:
            _l.sqlite3_finalize(st)

    def __enter__(self):
        return self

    def __exit__(self, *a):
        _l.sqlite3_close(self.h)


def _version():
    """SQLCipher-Version der geladenen Bibliothek, z. B. "3.4.1" oder "4.6.1 community"."""
    x = Db.__new__(Db)
    x.h = _p()
    _l.sqlite3_open_v2(b":memory:", ctypes.byref(x.h), 0x2 | 0x4, None)
    try:
        return x.abfrage("PRAGMA cipher_version")[0][0]
    except (RuntimeError, IndexError):
        return "?"
    finally:
        _l.sqlite3_close(x.h)


def zeitpunkt(t):
    try:
        return datetime.datetime.fromisoformat(t).timestamp()
    except (TypeError, ValueError):
        return time.time()


def protokoll(quelle, eintraege):
    # fuer eigene Skripte: Eintraege = dicts (mit "t" als ISO-Zeit), Quelle z. B. ereignisse oder admin
    with Db() as db:
        db.viele("insert into protokoll (quelle, zeit, zeile) values (?, ?, ?)",
                 [(quelle, zeitpunkt(e.get("t")), json.dumps(e, ensure_ascii=False)) for e in eintraege])


def _test():
    import tempfile
    d = tempfile.mkdtemp()
    db, key = d + "/t.db", d + "/t.key"

    def schluessel_neu():
        with open(key, "w") as f:
            f.write(os.urandom(32).hex())

    def seite(x):
        return x.abfrage("PRAGMA cipher_page_size")[0][0]
    schluessel_neu()
    try:
        with Db(db, key) as x:
            assert x.kompat == 3
            fmt3 = seite(x)
            x.viele("insert into protokoll (quelle, zeit, zeile) values (?, ?, ?)",
                    [("admin", 1.5, '{"a": "GEHEIMTEST ä"}'), ("admin", 2.0, "zwei"), ("ereignisse", 3, "x\x00y")])
            assert x.abfrage("select quelle, zeit, zeile from protokoll where quelle = ? order by zeit", ("admin",)) == \
                [("admin", 1.5, '{"a": "GEHEIMTEST ä"}'), ("admin", 2.0, "zwei")]
            assert x.abfrage("select zeile from protokoll where quelle = ?", ("ereignisse",)) == [("x\x00y",)]
            assert x.abfrage("select count(*) from protokoll where zeile like ?", ("%GEHEIM%",)) == [(1,)]
        roh = b""
        for p in (db, db + "-wal"):
            if os.path.exists(p):
                with open(p, "rb") as f:
                    roh += f.read()
        assert b"GEHEIMTEST" not in roh and b"SQLite format 3" not in roh, "Datei nicht verschluesselt"
        # Datei im Standardformat der Bibliothek (4.x: Format 4, so schrieb sie die Fassung vor cipher_compatibility):
        # Db oeffnet sie im zweiten Versuch. Auf 3.x ist das Format dasselbe.
        alt = d + "/alt.db"
        with Db(alt, key, versuche=(None,)) as x:
            fmt_std = seite(x)
            x.viele("insert into protokoll (quelle, zeit, zeile) values (?, ?, ?)", [("admin", 1, "alt")])
        with Db(alt, key) as x:
            assert x.abfrage("select zeile from protokoll") == [("alt",)] and seite(x) == fmt_std, (seite(x), fmt_std)
        with Db(db, key, versuche=(3,)) as x:   # die neue Datei braucht keinen zweiten Versuch
            assert x.abfrage("select count(*) from protokoll") == [(3,)]
        if fmt_std != fmt3:   # 4.x: die Formate unterscheiden sich wirklich, jede Datei geht nur mit ihrem eigenen
            for datei, versuche in ((db, (None,)), (alt, (3,))):
                try:
                    Db(datei, key, versuche=versuche)
                    raise AssertionError("Format 3 und Format 4 lassen sich nicht unterscheiden")
                except RuntimeError:
                    pass
        schluessel_neu()   # falscher Schluessel, Datei im Standardformat und im Format 3, fremde Datei
        with open(d + "/muell.db", "wb") as f:
            f.write(os.urandom(8192))
        for datei in (db, alt, d + "/muell.db"):
            try:
                Db(datei, key)
                raise AssertionError("falscher Schluessel oder fremde Datei wurde angenommen: " + datei)
            except RuntimeError as e:
                assert "not a database" in str(e) or "encrypted" in str(e), e
        with open(key, "w") as f:
            f.write("kein hex")
        try:
            Db(db, key)
            raise AssertionError("ungueltiger Schluessel wurde angenommen")
        except ValueError:
            pass
        version = _version()
    finally:
        for p in os.listdir(d):
            os.unlink(os.path.join(d, p))
        os.rmdir(d)
    print("Selbsttest ok: schreiben, lesen, Datei ohne Klartext, falscher Schluessel und fremde Datei abgewiesen, Format 3 "
          "(Seitengroesse %s) und Bibliotheksstandard (%s) lesbar, SQLCipher %s" % (fmt3, fmt_std, version))


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["test"]:
        _test()
    elif a[:1] == ["protokoll"] and len(a) >= 2:
        von = zeitpunkt(a[2]) if len(a) > 2 else 0
        bis = zeitpunkt(a[3]) + 86400 if len(a) > 3 else 1e11
        try:
            with Db() as db:
                for (z,) in db.abfrage("select zeile from protokoll where quelle = ? and zeit >= ? and zeit < ? order by zeit, id",
                                       (a[1], von, bis)):
                    print(z)
        except (RuntimeError, ValueError, OSError) as e:   # Schluessel fehlt, falsch, Bibliothek passt nicht: eine Zeile
            sys.exit("pacsdb.py: %s" % e)
    else:
        print("pacsdb.py test | protokoll QUELLE [VON [BIS]]   (QUELLE: zugriffe, ereignisse, admin)")
        sys.exit(1)
