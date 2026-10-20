"""Generate a private-namespace rollback test; never restart live Android services."""
from pathlib import Path
P=Path(__file__).resolve().parent
src=(P/'assets/restore.sh').read_text(encoding='utf-8')
functions=src.split('mkdir -p "$B"; chmod 700 "$B"')[0]
functions=functions.replace('/data/adb/ksu/bin/resetprop -n sys.boot_completed 0','true # no property writes in test')
out='''#!/system/bin/sh
set -eu
BB=/data/adb/ksu/bin/busybox
if [ "${1:-}" != inner ]; then exec "$BB" unshare -m --propagation private sh "$0" inner; fi
'''+functions+'''
TEST=$(mktemp -d /data/local/tmp/google-rollback-test.XXXXXX)
mount -t tmpfs -o size=4m tmpfs "$TEST"
B=$TEST
R=$B/runtime
cleanup_test() {
  umount -l /system/priv-app 2>/dev/null || true
  umount -l /system/etc/permissions 2>/dev/null || true
  umount -l "$R" 2>/dev/null || true
  cd /
  umount -l "$TEST" 2>/dev/null || true
  rmdir "$TEST"
}
trap cleanup_test EXIT
stop() { echo stop >> "$B/events"; }
start() {
  if own_mount /system/priv-app || own_mount /system/etc/permissions; then
    echo 'FAIL: start called before both mounts were detached'; return 1
  fi
  echo start >> "$B/events"
}
wait_boot() { return 0; }
mkdir "$R"
mount -t tmpfs -o size=1m tmpfs "$R"
mkdir -p "$R/priv-app" "$R/etc/permissions"
mount -t overlay -o "ro,lowerdir=$R/priv-app:/system/priv-app" KSU /system/priv-app
mount -t overlay -o "ro,lowerdir=$R/etc/permissions:/system/etc/permissions" KSU /system/etc/permissions
cd /system/priv-app
if umount /system/priv-app 2>/dev/null; then echo 'FAIL: busy mount case not reproduced'; exit 1; fi
rollback_mounts
test "$(cat "$B/events")" = "$(printf 'stop\\nstart')"
! own_mount /system/priv-app
! own_mount /system/etc/permissions
echo 'PASS: busy application mount reproduced; both layers detached before simulated start'
echo 'PASS: no real Android stop/start or property write executed'
'''
(P/'build/test-rollback.sh').write_text(out,encoding='utf-8',newline='\n')
