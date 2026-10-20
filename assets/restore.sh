#!/system/bin/sh
# Device-specific, manually initiated restore. No exploit, boot hooks or partition writes.
set -eu
B=/data/adb/google-restore
R=$B/runtime
PUB=/data/local/tmp/google-restore-helper
BB=/data/adb/ksu/bin/busybox
GMS=com.google.android.gms
STORE=com.android.vending
TAG=google-restore-app

say() { printf '%s\n' "$*"; }
status() { printf '%s\n' "$*" > "$B/status.new"; mv "$B/status.new" "$B/status"; say "$*"; }
boot() { cat /proc/sys/kernel/random/boot_id; }
acquire_lock() {
  LOCK="$B/lock-$(boot)"
  if [ -d "$LOCK" ]; then
    pid=$(cat "$LOCK/pid" 2>/dev/null || true)
    case "$pid" in ''|*[!0-9]*) return 2;; esac
    if kill -0 "$pid" 2>/dev/null; then return 2; fi
    rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null || return 2
  fi
  mkdir "$LOCK" 2>/dev/null || return 2
  printf '%s\n' "$$" > "$LOCK/pid"
}
release_lock() {
  [ -n "${LOCK:-}" ] || return 0
  if [ "$(cat "$LOCK/pid" 2>/dev/null || true)" = "$$" ]; then rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null || true; fi
}
supported() {
  [ "$(getprop ro.product.model)" = LSA-AN00 ] && [ "$(getprop ro.build.version.sdk)" = 34 ] || return 1
  case "$(getprop ro.build.display.id)" in
    'LSA-AN00 8.0.0.221'|'LSA-AN00 8.0.0.221('*')') return 0;;
    *) return 1;;
  esac
}
preflight() {
  [ "$(id -u)" = 0 ] || { say '需要 Root 授权'; exit 1; }
  supported || { say '当前版本尚未适配，停止操作'; exit 1; }
  [ -x "$BB" ] || { say '未发现配套 KernelSU 工具'; exit 1; }
  [ "$(readlink /proc/self/ns/mnt)" = "$(readlink /proc/1/ns/mnt)" ] || { say '未进入全局挂载空间'; exit 1; }
}
has_mount() { awk -v p="$1" '$5==p {found=1} END {exit !found}' /proc/self/mountinfo; }
own_mount() { grep -F "lowerdir=$R/" /proc/self/mountinfo | grep -F " $1 " >/dev/null; }
policy() { su 1000 -c "CLASSPATH=$PUB/control.jar app_process / RestorePolicy $1 $2"; }
packages_ready() {
  for pkg in com.google.android.gsf "$GMS" "$STORE"; do
    pm path "$pkg" 2>/dev/null | grep -q '^package:' || return 1
  done
}
wait_boot() {
  i=0
  while [ "$i" -lt 100 ]; do
    if [ "$(getprop sys.boot_completed)" = 1 ] && packages_ready; then return 0; fi
    sleep 2; i=$((i+1))
  done
  return 1
}
wait_android() {
  n=0
  while [ "$n" -lt 100 ]; do
    if [ "$(getprop sys.boot_completed)" = 1 ] && service check package | grep -q 'found'; then return 0; fi
    sleep 2; n=$((n+1))
  done
  return 1
}
snapshot() {
  if [ ! -f "$B/snapshot-boot" ] || [ "$(cat "$B/snapshot-boot")" != "$(boot)" ]; then
    mkdir -p "$B/before" || return 1
    rm -f "$B/before/gms" "$B/before/store" "$B/before/firewall-added" || return 1
    boot > "$B/snapshot-boot" || return 1
  fi
}
repair() {
  snapshot || return 1
  mkdir -p "$PUB" && chmod 755 "$PUB" || return 1
  cp "$B/control.jar" "$PUB/control.jar" && chmod 644 "$PUB/control.jar" || return 1
  for pair in "gms:$GMS" "store:$STORE"; do
    key=${pair%%:*}; pkg=${pair#*:}
    info=$(policy query "$pkg") || return 1
    if [ ! -f "$B/before/$key" ]; then printf '%s\n' "$info" > "$B/before/$key" || return 1; fi
    case "$info" in *restricted=true*) policy allow "$pkg" || return 1;; esac
  done
  # Add only a GMS classifier exception to the vendor chain; preserve all other rules.
  if iptables -S haware_uid_black_list >/dev/null 2>&1; then
    if ! iptables -S haware_uid_black_list | grep -E '^\-A haware_uid_black_list -m bpf --object-pinned /sys/fs/bpf/prog_hwnetd_skfilter_gms_uid_match_xtbpf( -m comment --comment [^ ]+)? -j RETURN$' >/dev/null; then
      iptables -I haware_uid_black_list 1 -m bpf --object-pinned /sys/fs/bpf/prog_hwnetd_skfilter_gms_uid_match_xtbpf -m comment --comment "$TAG" -j RETURN || return 1
      touch "$B/before/firewall-added" || return 1
    fi
  else
    say '没有预期的网络规则，停止自动修复'; return 1
  fi
  if ! cmd deviceidle whitelist | grep -q ",$STORE,"; then
    cmd deviceidle whitelist +"$STORE" || return 1
    touch "$B/before/whitelist-added" || return 1
  fi
  # Nearby WiFi permission is not needed for login; leave user runtime grants unchanged.
  say '联网状态与商店后台配置已核验'
}
undo_settings() {
  [ -f "$B/snapshot-boot" ] && [ "$(cat "$B/snapshot-boot")" = "$(boot)" ] || return 0
  for pair in "gms:$GMS" "store:$STORE"; do
    key=${pair%%:*}; pkg=${pair#*:}
    if [ -f "$B/before/$key" ] && grep -q 'restricted=true' "$B/before/$key"; then
      olduid=$(sed -n 's/^uid=\([0-9]*\).*/\1/p' "$B/before/$key")
      now=$(policy query "$pkg" 2>/dev/null || true)
      case "$now" in "uid=$olduid "*) policy block "$pkg" || say '框架规则恢复失败';; *) say 'UID 已变化，未恢复旧限制';; esac
    fi
  done
  if [ -f "$B/before/firewall-added" ]; then
    if iptables -C haware_uid_black_list -m bpf --object-pinned /sys/fs/bpf/prog_hwnetd_skfilter_gms_uid_match_xtbpf -m comment --comment "$TAG" -j RETURN 2>/dev/null; then
      iptables -D haware_uid_black_list -m bpf --object-pinned /sys/fs/bpf/prog_hwnetd_skfilter_gms_uid_match_xtbpf -m comment --comment "$TAG" -j RETURN || return 1
    fi
    rm -f "$B/before/firewall-added"
  fi
  if [ -f "$B/before/whitelist-added" ]; then
    cmd deviceidle whitelist -"$STORE" || return 1
    rm -f "$B/before/whitelist-added"
  fi
}
rollback_mounts() {
  # Called only for mounts owned by this app. Never touch unknown/older trial layers.
  if ! own_mount /system/priv-app && ! own_mount /system/etc/permissions; then
    if has_mount "$R"; then umount -l "$R" || return 1; start || return 1; wait_android || return 1; fi
    return 0
  fi
  stop || return 1
  failed=0
  for target in /system/priv-app /system/etc/permissions; do
    if own_mount "$target"; then umount -l "$target" || failed=1; fi
  done
  if grep -F "lowerdir=$R/" /proc/self/mountinfo >/dev/null; then failed=1; fi
  if [ "$failed" -ne 0 ]; then
    # Do not start Android with only one half of this layer remaining.
    for rel in priv-app etc/permissions; do
      if ! has_mount "/system/$rel"; then
        mount -t overlay -o "ro,lowerdir=$R/$rel:/system/$rel" KSU "/system/$rel" || {
          status '恢复受阻，请连接电脑处理；未整机重启'; return 1;
        }
      fi
    done
    start || return 1
    status '撤销未完成，已恢复两处挂载，需人工检查'; return 1
  fi
  umount -l "$R" 2>/dev/null || true
  /data/adb/ksu/bin/resetprop -n sys.boot_completed 0
  start || return 1
  wait_android || { status '已撤销挂载，但系统启动尚未确认'; return 1; }
}
health() {
  packages_ready || return 1
  for pkg in com.google.android.gsf "$GMS" "$STORE"; do
    dumpsys package "$pkg" | awk '/PRIVILEGED/ {ok=1} END {exit !ok}' || return 1
  done
  policy query "$GMS" | grep -q 'restricted=false'
}
readonly_status() {
  say "系统：$(getprop ro.product.model) / Android $(getprop ro.build.version.release)"
  say 'Root：已授权'
  if ! supported; then say '适配检查：当前系统版本不受支持'; return; fi
  if [ -f "$B/status" ]; then cat "$B/status"; fi
  if packages_ready; then
    say '组件：三件套均已注册'
    if own_mount /system/priv-app; then say '挂载：由本 App 管理';
    elif has_mount /system/priv-app; then say '挂载：已有部署，本 App 不重复挂载';
    else say '挂载：未发现本 App 的临时层'; fi
    if [ -f "$PUB/control.jar" ]; then
      info=$(policy query "$GMS" 2>/dev/null || true)
      case "$info" in *restricted=false*) say '谷歌联网：系统允许';; *restricted=true*) say '谷歌联网：需要修复系统限制';; *) say '谷歌联网：尚未核验';; esac
    fi
  else say '组件：需要恢复部署'; fi
  [ "$(getprop sys.boot_completed)" = 1 ] && say 'Android：启动完成'
}

mkdir -p "$B"; chmod 700 "$B"
case "${1:-status}" in
  status) readonly_status; exit 0;;
  watchdog)
    sleep 240
    [ -f "$B/session" ] && [ "$(cat "$B/session")" = "$2" ] || exit 0
    [ -f "$B/done" ] && [ "$(cat "$B/done")" = "$2" ] && exit 0
    if tr '\000' ' ' < "/proc/$3/cmdline" 2>/dev/null | grep -F "sh $B/restore.sh restore" >/dev/null; then kill -TERM "$3" 2>/dev/null || true; fi
    n=0
    until acquire_lock; do n=$((n+1)); [ "$n" -lt 10 ] || { status '操作超时且仍占用锁，请连接电脑检查'; exit 1; }; sleep 2; done
    trap release_lock EXIT
    [ -f "$B/done" ] && [ "$(cat "$B/done")" = "$2" ] && exit 0
    status '恢复超时，尝试撤销临时挂载'
    rollback_mounts || exit 1
    status '超时撤销完成，请重新检查状态'
    exit 0;;
esac
preflight
acquire_lock || { say '已有操作正在运行，请勿重复点击'; exit 2; }
trap release_lock EXIT
case "$1" in
  check) (cd "$B/payload" && "$BB" sha256sum -c "$B/payload.sha256" >/dev/null); say '文件完整性通过'; exit 0;;
  repair)
    status '正在核验联网与后台配置'
    repair || { status '修复未完成，请查看日志'; exit 1; }
    status '配置已恢复；请在商店验证登录和下载'; exit 0;;
  undo)
    status '正在撤销本 App 的更改'
    undo_settings
    rollback_mounts || exit 1
    status '本 App 的更改已撤销；已有外部挂载未移除'; exit 0;;
  restore) ;;
  *) say '不支持的操作'; exit 1;;
esac
status '正在检查组件和文件'
(cd "$B/payload" && "$BB" sha256sum -c "$B/payload.sha256" >/dev/null) || { status '文件校验失败，未更改系统'; exit 1; }
if packages_ready && dumpsys package "$GMS" | awk '/pkgFlags=.*SYSTEM/ {ok=1} END {exit !ok}'; then
  repair || { status '现有组件配置修复失败，请查看日志'; exit 1; }
  status '现有组件已恢复配置，没有重复挂载或重启系统'; exit 0
fi
for target in /system/priv-app /system/etc/permissions; do
  if has_mount "$target"; then status '发现已有挂载，停止操作以避免覆盖'; exit 1; fi
done
avail=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
[ "$avail" -gt 1000000 ] || { status '可用内存不足 1GB，请关闭应用后重试'; exit 1; }
mkdir -p "$R"
has_mount "$R" && { status '运行目录已有挂载，请检查后再试'; exit 1; }
mount -t tmpfs -o size=640m,mode=0755 tmpfs "$R"
trap 'umount -l "$R" 2>/dev/null || true; release_lock' EXIT
cp -R "$B/payload/system/." "$R/"
chown -R 0:0 "$R"; chcon -R u:object_r:system_file:s0 "$R"
find "$R" -type d -exec chmod 755 {} \;
find "$R" -type f -exec chmod 644 {} \;
session="$(boot)-$$"
printf '%s\n' "$session" > "$B/session"
"$BB" nohup "$BB" setsid /system/bin/sh "$B/restore.sh" watchdog "$session" "$$" > "$B/watchdog.log" 2>&1 < /dev/null &
watchdog=$!
sleep 1; kill -0 "$watchdog"
failed_restore() {
  trap - EXIT TERM
  say '恢复失败，尝试完整撤销'
  rollback_mounts || { release_lock; return 1; }
  printf '%s\n' "$session" > "$B/done"
  status '恢复失败，临时挂载已撤销；请查看日志'
  release_lock
}
trap failed_restore EXIT
trap 'exit 143' TERM
status '正在重启 Android 服务，App 暂时关闭属于正常现象'
stop
mount -t overlay -o "ro,lowerdir=$R/priv-app:/system/priv-app" KSU /system/priv-app
mount -t overlay -o "ro,lowerdir=$R/etc/permissions:/system/etc/permissions" KSU /system/etc/permissions
/data/adb/ksu/bin/resetprop -n sys.boot_completed 0
start
wait_boot || exit 1
status '正在恢复谷歌联网和商店后台配置'
repair || exit 1
health || exit 1
printf '%s\n' "$session" > "$B/done"
trap release_lock EXIT
trap - TERM
status '恢复完成；请打开 Play 商店验证登录和下载'
