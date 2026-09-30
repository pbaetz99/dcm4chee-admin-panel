#!/usr/bin/env python3
# Verschluesselte SQLite-Datenbank (SQLCipher, Debian/Ubuntu-Paket libsqlcipher0) fuer das Protokoll der Verwaltungsseite.
# Encrypted audit log store (SQLCipher via ctypes), stdlib only, Python 3.7+.
#   PROTOKOLL_DB   Standard /var/lib/pacs-protokoll/protokoll.db. Tabelle protokoll: Zugriffe, Ereignisse, Verwaltung,
#                  je Zeile das JSON, das nginx per syslog schickt (verwaltung-dienst.py legt es ab)
#   PROTOKOLL_KEY  Standard /etc/pacs-protokoll.key. Schluessel, 64 Hex-Zeichen, nur root lesbar, z. B.
#                  (umask 077; openssl rand -hex 32 > /etc/pacs-protokoll.key). Eine Kopie gehoert in den
#                  Passwort-Tresor: ohne den Schluessel ist die Datenbank nicht mehr lesbar.
# Lesen als root: pacsdb.py protokoll QUELLE [VON [BIS]]  |  pacsdb.py test (Selbsttest)
# Von Hand: sqlcipher DATEI, dann PRAGMA key = "x'<Schluessel>'";
import ctypes, ctypes.util, datetime, json, os, re, sys, time

DB = os.environ.get("PROTOKOLL_DB") or "/var/lib/pacs-protokoll/protokoll.db"
SCHLUESSEL = os.environ.get("PROTOKOLL_KEY") or "/etc/pacs-protokoll.key"
SCHEMA = [
    "PRAGMA journal_mode = WAL",
    "create table if not exists protokoll (id integer primary key, quelle text not null, zeit real not null, zeile text not null)",
    "create index if not exists protokoll_zeit on protokoll (quelle, zeit)",
]


def _bibliothek():
    for name in (ctypes.util.find_library("sqlcipher"), "libsqlcipher.so.0", "libsqlcipher.so"):
        if name:
            try:
                return ctypes.CDLL(name)
            except OSError:
                pass
    raise ImportError("libsqlcipher nicht gefunden. Debian/Ubuntu: apt install libsqlcipher0 "
                      "(SQLCipher library not found, install libsqlcipher0 or your distribution's sqlcipher package)")


_l = _bibliothek()
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
    def __init__(self, pfad=DB, schluessel=SCHLUESSEL):
        k = open(schluessel).read().strip()
        if not re.fullmatch(r"[0-9a-f]{64}", k):
            raise ValueError("Schluessel in %s ist nicht 64 Hex-Zeichen (kleingeschrieben)" % schluessel)
        self.h = _p()
        neu = not os.path.exists(pfad)
        if neu:
            os.makedirs(os.path.dirname(os.path.abspath(pfad)), mode=0o700, exist_ok=True)
        if _l.sqlite3_open_v2(pfad.encode(), ctypes.byref(self.h), 0x2 | 0x4 | 0x10000, None):   # RW, CREATE, FULLMUTEX
            raise RuntimeError("%s: %s" % (pfad, self._fehler()))
        if neu:
            os.chmod(pfad, 0o600)
        _l.sqlite3_busy_timeout(self.h, 15000)
        self.ausfuehren("PRAGMA key = \"x'%s'\"" % k)   # Rohschluessel, keine Ableitung
        for s in SCHEMA:   # prueft zugleich den Schluessel: falsch = "file is encrypted or is not a database"
            self.ausfuehren(s)

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
    open(key, "w").write(os.urandom(32).hex())
    try:
        with Db(db, key) as x:
            x.viele("insert into protokoll (quelle, zeit, zeile) values (?, ?, ?)",
                    [("admin", 1.5, '{"a": "GEHEIMTEST ä"}'), ("admin", 2.0, "zwei"), ("ereignisse", 3, "x\x00y")])
            assert x.abfrage("select quelle, zeit, zeile from protokoll where quelle = ? order by zeit", ("admin",)) == \
                [("admin", 1.5, '{"a": "GEHEIMTEST ä"}'), ("admin", 2.0, "zwei")]
            assert x.abfrage("select zeile from protokoll where quelle = ?", ("ereignisse",)) == [("x\x00y",)]
            assert x.abfrage("select count(*) from protokoll where zeile like ?", ("%GEHEIM%",)) == [(1,)]
        roh = b"".join(open(p, "rb").read() for p in (db, db + "-wal") if os.path.exists(p))
        assert b"GEHEIMTEST" not in roh and b"SQLite format 3" not in roh, "Datei nicht verschluesselt"
        open(key, "w").write(os.urandom(32).hex())
        try:
            Db(db, key)
            raise AssertionError("falscher Schluessel wurde angenommen")
        except RuntimeError as e:
            assert "not a database" in str(e) or "encrypted" in str(e), e
    finally:
        for p in os.listdir(d):
            os.unlink(os.path.join(d, p))
        os.rmdir(d)
    print("Selbsttest ok: schreiben, lesen, Datei ohne Klartext, falscher Schluessel abgewiesen")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["test"]:
        _test()
    elif a[:1] == ["protokoll"] and len(a) >= 2:
        von = zeitpunkt(a[2]) if len(a) > 2 else 0
        bis = zeitpunkt(a[3]) + 86400 if len(a) > 3 else 1e11
        with Db() as db:
            for (z,) in db.abfrage("select zeile from protokoll where quelle = ? and zeit >= ? and zeit < ? order by zeit, id",
                                   (a[1], von, bis)):
                print(z)
    else:
        print("pacsdb.py test | protokoll QUELLE [VON [BIS]]   (QUELLE: zugriffe, ereignisse, admin)")
        sys.exit(1)
