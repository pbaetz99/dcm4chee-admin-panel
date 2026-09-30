#!/usr/bin/env python3
# Demo der PACS-Verwaltung mit erfundenen Daten: liefert web/ aus und haengt in /admin/ demo/mock.js vor config.js
# ein, das alle Serveraufrufe der Seite beantwortet. Kein dcm4chee, kein Dienst, kein nginx noetig.
# Demo server: serves web/ with fake data (demo/mock.js). Usage: python demo/serve.py [port]   (default 8000)
import http.server, os, sys

DEMO = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(DEMO)
CONFIG = '<script src="/admin/config.js"></script>'


class Anfrage(http.server.SimpleHTTPRequestHandler):
    # Windows liest Dateitypen aus der Registry, dort steht .js/.css mitunter falsch
    extensions_map = dict(http.server.SimpleHTTPRequestHandler.extensions_map,
                          **{'.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json'})

    def translate_path(self, path):   # /demo/... aus demo/, alles andere aus web/; ".." bleibt im jeweiligen Verzeichnis
        demo = path.startswith('/demo/')
        self.directory = DEMO if demo else os.path.join(WURZEL, 'web')
        return super().translate_path(path[5:] if demo else path)

    def do_GET(self):
        if self.path.split('?')[0] not in ('/admin/', '/admin/index.html'):
            return super().do_GET()
        with open(os.path.join(WURZEL, 'web', 'admin', 'index.html'), encoding='utf-8') as f:
            b = f.read().replace(CONFIG, '<script src="/demo/mock.js"></script>' + CONFIG, 1).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(b)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(b)


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    server = http.server.ThreadingHTTPServer(('127.0.0.1', port), Anfrage)
    print('Demo: http://127.0.0.1:%d/admin/   (Strg+C beendet)' % port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
