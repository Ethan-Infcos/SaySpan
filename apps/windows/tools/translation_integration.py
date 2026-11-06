"""Exercise real TSF → companion → HTTP → TSF insertion in isolated Windows CI."""
import contextlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
import winreg


def run(binary: Path, payload: Path):
    if os.environ.get('CI') != 'true':
        raise RuntimeError('Translation integration is restricted to isolated CI accounts')

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # Never log source text or authorization headers.

        def do_POST(self):
            length = int(self.headers.get('Content-Length', '0'))
            if length > 65536:
                self.send_error(413)
                return
            body = json.loads(self.rfile.read(length))
            assert self.path == '/api/chat'
            assert body['messages'][1]['role'] == 'user'
            data = json.dumps({'message': {'content': '__TRANSLATED__'}}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    names = {'Provider': 'ollama', 'OllamaUrl': f'http://127.0.0.1:{server.server_port}',
             'OllamaModel': 'synthetic-test', 'SelectionEnabled': 0,
             'FirstLanguage': 'en', 'SecondLanguage': 'zh'}
    key = winreg.CreateKey(winreg.HKEY_CURRENT_USER, r'Software\SaySpan')
    saved = {}
    for name, value in names.items():
        try:
            saved[name] = winreg.QueryValueEx(key, name)
        except FileNotFoundError:
            saved[name] = None
        winreg.SetValueEx(key, name, 0, winreg.REG_DWORD if isinstance(value, int) else winreg.REG_SZ, value)
    companion = subprocess.Popen([str(payload / 'companion/SaySpan.exe'), '--background'])
    register = payload / 'SaySpanRegister.exe'
    try:
        subprocess.run([str(register), '--register'], check=True)
        time.sleep(1)
        subprocess.run([str(binary / 'host_tests.exe'), '--translation'], check=True, timeout=60)
    finally:
        subprocess.run([str(register), '--unregister'], check=True)
        companion.terminate()
        companion.wait(timeout=10)
        server.shutdown()
        for name, value in saved.items():
            if value is None:
                with contextlib.suppress(FileNotFoundError):
                    winreg.DeleteValue(key, name)
            else:
                winreg.SetValueEx(key, name, 0, value[1], value[0])
        winreg.CloseKey(key)


if __name__ == '__main__':
    run(Path(sys.argv[1]), Path(sys.argv[2]))
