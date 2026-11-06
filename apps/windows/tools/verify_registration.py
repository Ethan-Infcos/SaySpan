"""Verify registration from fresh processes, with a bounded catalog refresh window."""
import subprocess
import time


def verify_registration(executable):
    deadline = time.monotonic() + 15
    last = None
    while True:
        last = subprocess.run([str(executable), '--verify'], capture_output=True, text=True)
        if last.returncode == 0:
            print(last.stdout, end='', flush=True)
            return
        if time.monotonic() >= deadline:
            print(last.stdout, end='', flush=True)
            print(last.stderr, end='', flush=True)
            raise RuntimeError('Windows did not expose the registered input profile within 15 seconds')
        time.sleep(0.5)
