"""Host-only checks: execute extracted compatibility predicate with mocked properties."""
import os, subprocess, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parent
SHELL = os.environ.get('TEST_SHELL', 'C:/Program Files/Git/bin/bash.exe' if os.name == 'nt' else '/bin/sh')
SCRIPT = (ROOT / 'assets/restore.sh').read_text(encoding='utf-8')
PREDICATE = SCRIPT[SCRIPT.index('supported() {'):SCRIPT.index('preflight() {')]

class CompatibilityTests(unittest.TestCase):
    def check_case(self, sdk, abi, expected):
        env = dict(os.environ, MOCK_SDK=sdk, MOCK_ABI=abi)
        stub = 'getprop() { case "$1" in ro.build.version.sdk) echo "$MOCK_SDK";; ro.product.cpu.abilist) echo "$MOCK_ABI";; *) exit 99;; esac; }\n'
        result = subprocess.run([SHELL, '-c', stub + PREDICATE + '\nsupported'], env=env, capture_output=True)
        self.assertEqual(result.returncode == 0, expected)
    def test_android14_arm64(self): self.check_case('34','arm64-v8a,armeabi-v7a',True)
    def test_newer_api_not_whitelisted(self): self.check_case('35','arm64-v8a',True)
    def test_payload_minimum(self): self.check_case('33','arm64-v8a',False)
    def test_wrong_abi(self): self.check_case('34','x86_64',False)
    def test_malformed_sdk(self): self.check_case('unknown','arm64-v8a',False)
    def test_missing_sdk(self): self.check_case('','arm64-v8a',False)
    def test_no_identity_properties(self):
        self.assertNotIn('ro.product.model',PREDICATE)
        self.assertNotIn('ro.build.display.id',PREDICATE)
        self.assertNotIn('uname',PREDICATE)
    def test_undo_dependency_bypass(self):
        self.assertIn('[ "${1:-}" = undo ] || supported',SCRIPT)
        self.assertIn('preflight "$1"',SCRIPT)
    def test_shell_syntax(self):
        result=subprocess.run([SHELL,'-n'],input=SCRIPT.encode(),capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr)

if __name__ == '__main__': unittest.main()
