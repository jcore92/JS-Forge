#!/bin/bash
jsf_no_pause="1"
umask 077
app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/JS-Forge/runtime-core.lib}"
source "$runtime_core_path" || { echo "Cannot load JS-Forge runtime: $runtime_core_path" >&2; exit 1; }
jsf_init_runtime_core
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
declare -F cursor_menu >/dev/null || { echo 'Missing runtime cursor_menu.' >&2; exit 1; }

root() { if (( EUID == 0 )); then "$@"; else sudo -- "$@"; fi; }
pause_screen() { printf '\n'; read -r -p 'Press Enter to continue...' _reply || :; }
confirm() { local reply; cursor_menu "$1" reply 'Cancel' 'Proceed' || return 1; [ "$reply" = Proceed ]; }
as_target() {
    if (( EUID == target_uid )); then "$@"; else
        command -v runuser >/dev/null || { echo 'runuser is required when configuring another account.' >&2; return 1; }
        root runuser -u "$target_user" -- "$@"
    fi
}
set_target() {
    local requested="$1" record ignored
    [ -n "$requested" ] && [[ "$requested" != -* ]] || return 1
    record="$(getent passwd "$requested")" || { echo 'Target account cannot be resolved.'; return 1; }
    [[ "$record" != *$'\n'* ]] || { echo 'Ambiguous account lookup.'; return 1; }
    IFS=: read -r target_user ignored target_uid target_gid ignored target_home ignored <<< "$record"
    [[ "$target_uid" =~ ^[0-9]+$ && "$target_gid" =~ ^[0-9]+$ && "$target_home" = /* ]] || return 1
    [ "$target_home" != / ] && [ -d "$target_home" ] || { echo 'Target home is missing/unsafe; no HOME fallback is used.'; return 1; }
    xsession_path="$target_home/.xsession"
}
change_target() {
    local requested
    read -r -p 'Target username or user@domain (empty cancels): ' requested || return 1
    [ -n "$requested" ] || return 0
    # Preserve the previous selection on failure.
    local old_user="$target_user" old_uid="$target_uid" old_gid="$target_gid" old_home="$target_home" old_path="$xsession_path"
    if ! set_target "$requested"; then
        target_user="$old_user";target_uid="$old_uid";target_gid="$old_gid";target_home="$old_home";xsession_path="$old_path";return 1
    fi
}
package_manager() {
    if command -v apt-get >/dev/null && command -v dpkg-query >/dev/null; then echo apt
    elif command -v dnf >/dev/null && command -v rpm >/dev/null; then echo dnf
    elif command -v zypper >/dev/null && command -v rpm >/dev/null; then echo zypper
    elif command -v yum >/dev/null && command -v rpm >/dev/null; then echo yum
    elif command -v pacman >/dev/null; then echo pacman
    else echo unknown; fi
}
package_present() {
    case "$(package_manager)" in
        apt) [ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" = 'install ok installed' ] ;;
        dnf|yum|zypper) rpm -q --quiet "$1" ;;
        pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}
ensure_packages() {
    local p manager; local -a missing=()
    manager="$(package_manager)"
    for p in "$@"; do package_present "$p" || missing+=("$p"); done
    [ "${#missing[@]}" -gt 0 ] || return 0
    printf '\nMissing packages:\n'; printf '  %s\n' "${missing[@]}"
    echo 'Package scripts may start services. Review the native package-manager transaction.'
    confirm 'Install the displayed missing packages?' || return 1
    case "$manager" in
        apt) root apt-get update && root apt-get install "${missing[@]}" || return 1 ;;
        dnf|yum) root "$manager" install "${missing[@]}" || return 1 ;;
        zypper) root zypper install "${missing[@]}" || return 1 ;;
        pacman) root pacman -S --needed "${missing[@]}" || return 1 ;;
        *) echo 'No usable package-manager command was found. No distribution-name gate is used.'; return 1 ;;
    esac
    for p in "${missing[@]}"; do package_present "$p" || { echo "Package still unavailable: $p"; return 1; }; done
}
supervised_dir() {
    local name="$1" base output
    command -v sv >/dev/null || return 1
    for base in /run/runit/service /run/service /service /var/service /etc/service /etc/runit/runsvdir/default; do
        [ -d "$base/$name/supervise" ] || continue
        output="$(sv status "$base/$name" 2>/dev/null)" || :
        case "$output" in run:*|down:*) printf '%s\n' "$base/$name"; return 0 ;; esac
    done
    return 1
}
service_manager() {
    if [ -d /run/systemd/system ] && command -v systemctl >/dev/null; then echo systemd
    elif supervised_dir xrdp >/dev/null; then echo runit
    elif [ -e /run/openrc/softlevel ] && command -v rc-service >/dev/null; then echo openrc
    elif [ -x /etc/init.d/xrdp ] && command -v service >/dev/null; then echo sysv
    else echo unknown; fi
}
compat_helper() {
    root env PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C python3 - "$@" <<'JSF_XRDP_COMPAT_PY'
import os,sys,re,stat,tempfile,subprocess,hashlib,datetime,uuid,grp,difflib
from pathlib import Path
INIT=Path('/etc/init.d/xrdp'); SOCK=Path('/run/xrdp/sockdir')
BACK=Path('/var/backups/JS-Forge/xrdp')
SOURCES=[Path('/usr/lib/tmpfiles.d/xrdp.conf'),Path('/lib/tmpfiles.d/xrdp.conf'),Path('/etc/tmpfiles.d/xrdp.conf')]
BEGIN='# BEGIN JS-Forge XRDP runtime directory'; END='# END JS-Forge XRDP runtime directory'
operation=sys.argv[1];expected=sys.argv[2] if len(sys.argv)>2 else ''
if os.geteuid()!=0 or operation not in ('plan','apply'):sys.exit('Invalid compatibility request.')
def regular(p):
 st=p.lstat()
 if p.is_symlink() or not stat.S_ISREG(st.st_mode) or st.st_uid!=0 or st.st_mode&0o022 or st.st_nlink!=1 or st.st_size>1048576:raise ValueError('Unsafe file: '+str(p))
 return st

def stage(data,st):
 fd,name=tempfile.mkstemp(prefix='.jsforge-xrdp-',dir=str(INIT.parent))
 try:
  with os.fdopen(fd,'wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
  os.chown(name,st.st_uid,st.st_gid);os.chmod(name,stat.S_IMODE(st.st_mode))
  p=subprocess.run(['sh','-n',name],capture_output=True,text=True)
  if p.returncode:raise ValueError('Init script syntax validation failed: '+p.stderr)
  return Path(name)
 except BaseException:Path(name).unlink(missing_ok=True);raise

def main():
 st=regular(INIT);old=INIT.read_bytes();text=old.decode('utf-8');mode='1777';group='root';origin='tested fallback (no installed tmpfiles entry found)'
 # Prefer /etc override, otherwise the installed vendor definition.
 for source in reversed(SOURCES):
  if not source.exists():continue
  regular(source)
  for line in source.read_text().splitlines():
   f=line.split()
   if len(f)>=5 and f[0] in ('d','D') and f[1] in ('/run/xrdp/sockdir','/var/run/xrdp/sockdir'):
    if not re.fullmatch(r'[0-7]{3,4}',f[2]) or f[3] not in ('root','0') or not re.fullmatch(r'[A-Za-z0-9_-]+',f[4]):raise ValueError('Unrecognized socket-directory definition: '+str(source))
    mode=f[2];group=f[4];origin=str(source);break
  if origin==str(source):break
 grp.getgrnam(group) if not group.isdigit() else grp.getgrgid(int(group))
 if text.count(BEGIN)!=text.count(END) or text.count(BEGIN)>1:raise ValueError('Malformed managed block; review init script manually.')
 cleaned=re.sub(re.escape(BEGIN)+r'.*?'+re.escape(END)+r'\n?', '',text,flags=re.S)
 # Absorb only the exact two-line workaround from the supplied working script.
 cleaned=re.sub(r'^mkdir -p /run/xrdp/sockdir\nchmod 1777 /run/xrdp/sockdir\n?', '',cleaned,flags=re.M)
 privilege=False;out=[]
 for line in cleaned.splitlines(keepends=True):
  if not line.lstrip().startswith('#') and '--chuid xrdp:xrdp' in line:
   privilege=True;line=line.replace('--chuid xrdp:xrdp','--chuid root:root')
  out.append(line)
 cleaned=''.join(out)
 block=(BEGIN+'\n# Recreate volatile XRDP sockets on each service invocation/boot.\n'
   'if [ -L /run/xrdp ] || [ -L /run/xrdp/sockdir ]; then\n'
   '    echo "XRDP: refusing a symlinked runtime directory" >&2\n    exit 1\nfi\n'
   'install -d -m '+mode+' -o root -g '+group+' /run/xrdp/sockdir || exit 1\n'+END+'\n')
 marker=re.search(r'^### END INIT INFO[^\n]*\n',cleaned,re.M)
 if marker:newtext=cleaned[:marker.end()]+block+cleaned[marker.end():]
 elif cleaned.startswith('#!') and '\n' in cleaned:
  first,rest=cleaned.split('\n',1);newtext=first+'\n'+block+rest
 else:raise ValueError('No recognizable init-script header; no blind edit attempted.')
 new=newtext.encode();token=hashlib.sha256(old+new+repr((st.st_ino,st.st_mode,st.st_uid,st.st_gid,st.st_mtime_ns)).encode()).hexdigest()
 for p in (SOCK.parent,SOCK):
  if p.is_symlink():raise ValueError('Symlinked runtime path: '+str(p))
  if p.exists() and not p.is_dir():raise ValueError('Non-directory runtime path: '+str(p))
 print('Runtime directory: '+str(SOCK)+'; mode='+mode+'; root:'+group+'; definition='+origin)
 if privilege:print('PRIVILEGE CHANGE: legacy --chuid xrdp:xrdp -> root:root, as in your tested setup. Other runtime_user settings are not rewritten.')
 if operation=='plan':
  if old!=new:print(''.join(difflib.unified_diff(text.splitlines(True),newtext.splitlines(True),fromfile=str(INIT),tofile=str(INIT)+' (proposed)')))
  else:print('Init script already matches; no rewrite needed.')
  print('Runtime directory permissions may be repaired even when the init script already matches.')
  print('PLAN_TOKEN='+token);return
 if token!=expected:raise ValueError('Init script changed since preview; nothing applied.')
 temporary=None;committed=False
 try:
  if old!=new:
   temporary=stage(new,st)
   for p in (BACK.parent,BACK):
    if p.is_symlink():raise ValueError('Symlinked backup directory.')
    p.mkdir(mode=0o700,parents=True,exist_ok=True)
    b=p.stat()
    if b.st_uid!=0 or b.st_mode&0o077:raise ValueError('Backup directory is not root-private: '+str(p))
   backup=BACK/('xrdp-init-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex+'.backup')
   with backup.open('xb') as f:f.write(old)
   os.chmod(backup,0o600);print('Private backup: '+str(backup))
   os.replace(temporary,INIT);committed=True
  # Directory descriptors prevent following a swapped socket-directory symlink.
  with_fd=[]
  try:
   runfd=os.open('/run',os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW);with_fd.append(runfd)
   try:os.mkdir('xrdp',0o755,dir_fd=runfd)
   except FileExistsError:pass
   parentfd=os.open('xrdp',os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=runfd);with_fd.append(parentfd)
   try:os.mkdir('sockdir',int(mode,8),dir_fd=parentfd)
   except FileExistsError:pass
   fd=os.open('sockdir',os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=parentfd);with_fd.append(fd)
   gid=int(group) if group.isdigit() else grp.getgrnam(group).gr_gid
   os.fchown(fd,0,gid);os.fchmod(fd,int(mode,8))
  finally:
   for fd in reversed(with_fd):os.close(fd)
  print('SysV compatibility setup applied. Restart XRDP to use changed startup settings.')
 except BaseException:
  if committed and INIT.read_bytes()==new:
   restore=stage(old,st);os.replace(restore,INIT);print('Init script restored after failure.',file=sys.stderr)
  raise
 finally:
  if temporary is not None:temporary.unlink(missing_ok=True)
try:main()
except Exception as e:print('Compatibility repair stopped: '+str(e),file=sys.stderr);sys.exit(1)
JSF_XRDP_COMPAT_PY
}

repair_sysv() {
    local preview token rc
    command -v python3 >/dev/null || { echo 'Install/repair XRDP first to provide Python 3.'; return 1; }
    [ -x /etc/init.d/xrdp ] || { echo 'No executable XRDP SysV script is present.'; return 1; }
    preview="$(compat_helper plan 2>&1)";rc=$?
    printf '%s\n' "$preview"
    [ "$rc" = 0 ] || return 1
    token="$(sed -nE 's/^PLAN_TOKEN=([a-f0-9]{64})$/\1/p' <<< "$preview")"
    [[ "$token" =~ ^[a-f0-9]{64}$ ]] || return 1
    echo 'This incorporates the supplied working SysV recipe, including its legacy root-startup workaround where matched.'
    echo 'Read any PRIVILEGE CHANGE warning above. Existing sessions are not restarted by this file repair.'
    confirm 'Apply the displayed SysV runtime/startup repair?' || return 1
    compat_helper apply "$token"
}
configure_certificate_access() {
    local config=/etc/xrdp/xrdp.ini
    getent passwd xrdp >/dev/null && getent group ssl-cert >/dev/null || return 0
    [ -f "$config" ] || return 0
    local key_setting
    key_setting="$(root awk '
        /^[[:space:]]*[#;]/ { next }
        /^[[:space:]]*key_file[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; found=1; exit
        }
        END { if (!found) print "(unspecified)" }
    ' "$config")" || return 1
    if [ -z "$key_setting" ] || [ "$key_setting" = '(unspecified)' ] || [ "$key_setting" = /etc/xrdp/key.pem ]; then
        if ! id -nG xrdp | tr ' ' '\n' | grep -Fxq ssl-cert; then
            echo 'Add the XRDP service account to ssl-cert for its configured packaged key access.'
            confirm 'Grant the xrdp service account ssl-cert group membership?' || return 1
            root usermod -aG ssl-cert xrdp || return 1
        fi
    else echo 'Custom/other TLS key configuration retained; verify its service-account access separately.'; fi
}
session_helper() {
    as_target python3 - "$target_home" "$@" <<'JSF_XRDP_SESSION_PY'
import os,sys,stat,tempfile,datetime,uuid
from pathlib import Path
home=Path(sys.argv[1]);action=sys.argv[2];arg=sys.argv[3] if len(sys.argv)>3 else ''
p=home/'.xsession'
def safe(path):
 if path.is_symlink():raise ValueError('Symlinked session file/backup requires manual review: '+str(path))
 if path.exists() and (not path.is_file() or path.stat().st_nlink!=1 or path.stat().st_size>1048576):raise ValueError('Unsafe session file: '+str(path))
def save_backup():
 if not p.exists():return
 safe(p);backup=home/('.xsession.jsf-backup-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex)
 with backup.open('xb') as f:f.write(p.read_bytes())
 os.chmod(backup,0o600);print('Backup: '+str(backup))
try:
 if os.geteuid()==0:raise ValueError('Choose a non-root XRDP desktop account.')
 if not home.is_dir():raise ValueError('Missing target home.')
 safe(p)
 if action=='restore':
  choices=[]
  for candidate in home.glob('.xsession.jsf-backup-*'):
   safe(candidate)
   if candidate.is_file():choices.append(candidate)
  if not choices:raise ValueError('No session backup found.')
  selected=max(choices,key=lambda f:f.stat().st_mtime_ns);raw=selected.read_bytes();print('Restoring: '+str(selected))
 elif action=='write':
  if not arg or '\n' in arg or '\r' in arg or '\0' in arg:raise ValueError('Enter a single-line desktop command.')
  raw=('#!/bin/sh\nexec '+arg+'\n').encode()
 else:raise ValueError('Unknown session operation.')
 if p.exists() and p.read_bytes()==raw:print('Session already matches.');sys.exit(0)
 save_backup()
 fd,name=tempfile.mkstemp(prefix='.jsforge-xsession-',dir=str(home))
 try:
  with os.fdopen(fd,'wb') as f:f.write(raw);f.flush();os.fsync(f.fileno())
  os.chmod(name,0o700);os.replace(name,p)
 finally:Path(name).unlink(missing_ok=True)
 print('Session configured: '+str(p))
except Exception as e:print('Session action stopped: '+str(e),file=sys.stderr);sys.exit(1)
JSF_XRDP_SESSION_PY
}
choose_desktop_session() {
    local selection command executable
    cursor_menu 'XRDP desktop session:' selection 'XFCE' 'KDE Plasma X11' 'MATE' 'Cinnamon' 'LXQt' 'GNOME (X11 required)' 'Custom command' 'Cancel' || return 1
    case "$selection" in
        XFCE)
            if ! command -v startxfce4 >/dev/null; then ensure_packages xfce4-session || return 1; fi
            command=startxfce4 ;;
        'KDE Plasma X11') command=startplasma-x11 ;;
        MATE) command=mate-session ;;
        Cinnamon) command=cinnamon-session ;;
        LXQt) command=startlxqt ;;
        'GNOME (X11 required)') command=gnome-session ;;
        'Custom command') read -r -p 'Single-line desktop command (runs as the target user): ' command || return 1 ;;
        *) return 1 ;;
    esac
    [ -n "$command" ] && [[ "$command" != *$'\n'* && "$command" != *$'\r'* ]] || return 1
    executable="${command%% *}"
    command -v "$executable" >/dev/null || { echo "Session command unavailable: $executable. Install that desktop first."; return 1; }
    command -v python3 >/dev/null || { ensure_packages python3 || return 1; }
    printf 'Target: %s (UID %s, GID %s)\nHome: %s\nSession command: %s\n' "$target_user" "$target_uid" "$target_gid" "$target_home" "$command"
    echo 'An existing .xsession is backed up before replacement. This file may also affect local X11 session selection.'
    confirm 'Write this target user session file?' || return 1
    session_helper write "$command"
}
install_xrdp() {
    local pm dbus_package python_package manager
    pm="$(package_manager)";dbus_package=dbus-x11;python_package=python3
    case "$pm" in pacman) dbus_package=dbus;python_package=python ;; zypper) dbus_package=dbus-1-x11 ;; esac
    ensure_packages xrdp xorgxrdp "$dbus_package" "$python_package" || return 1
    command -v python3 >/dev/null || { echo 'python3 is still unavailable.'; return 1; }
    configure_certificate_access || return 1
    manager="$(service_manager)"
    if [ "$manager" = sysv ]; then repair_sysv || return 1; fi
    if as_target test -e "$xsession_path" || as_target test -L "$xsession_path"; then
        echo "Existing $xsession_path retained. Use the session menu to inspect/replace it."
    else choose_desktop_session || return 1; fi
    echo 'Install/repair completed. Use Start and enable XRDP to start/restart it.'
}
sysv_boot() {
    local action="$1"
    if command -v update-rc.d >/dev/null; then
        if [ "$action" = enable ]; then root update-rc.d xrdp defaults && root update-rc.d xrdp enable
        else root update-rc.d xrdp disable; fi
    elif command -v chkconfig >/dev/null; then root chkconfig xrdp "$( [ "$action" = enable ] && echo on || echo off )"
    else echo 'No boot-registration tool found. Runtime service action is possible; boot state was not changed.'; return 1; fi
}
start_xrdp_service() {
    local manager dir name
    install_xrdp || return 1
    manager="$(service_manager)"
    echo "Service backend: $manager. Restarting can interrupt remote sessions."
    confirm 'Start/restart XRDP and enable its native boot startup?' || return 1
    case "$manager" in
        systemd) root systemctl enable xrdp.service && root systemctl restart xrdp.service || return 1 ;;
        sysv) sysv_boot enable && root service xrdp restart || return 1 ;;
        openrc) root rc-update add xrdp default && root rc-service xrdp restart || return 1 ;;
        runit)
            for name in xrdp-sesman xrdp; do
                dir="$(supervised_dir "$name")" || { [ "$name" = xrdp-sesman ] && continue; echo 'XRDP is not actively supervised.'; return 1; }
                root rm -f -- "$dir/down" && root sv -w 15 up "$dir" || return 1
            done ;;
        *) echo 'No actual XRDP service definition/supervisor was found. No commands were guessed from installed utilities.'; return 1 ;;
    esac
    sleep 2
    show_status
    if command -v pgrep >/dev/null; then
        pgrep -x xrdp >/dev/null && pgrep -x xrdp-sesman >/dev/null || { echo 'XRDP or sesman is not running. Review both logs.'; return 1; }
    fi
    echo 'Native service action completed. Verify a real RDP desktop login; process status alone is not a session test.'
}
stop_xrdp_service() {
    local manager dir name
    manager="$(service_manager)"
    echo 'This stops remote-desktop services and may disconnect users.'
    confirm 'Stop XRDP and disable its native boot startup?' || return 1
    case "$manager" in
        systemd)
            root systemctl stop xrdp.service || return 1
            if root systemctl cat xrdp-sesman.service >/dev/null 2>&1; then root systemctl stop xrdp-sesman.service || return 1; fi
            root systemctl disable xrdp.service ;;
        sysv) root service xrdp stop && sysv_boot disable ;;
        openrc) root rc-service xrdp stop && root rc-update del xrdp default ;;
        runit)
            for name in xrdp xrdp-sesman; do
                dir="$(supervised_dir "$name")" || continue
                root touch -- "$dir/down" && root sv -w 15 down "$dir" || return 1
            done ;;
        *) echo 'No actual XRDP service definition/supervisor found.'; return 1 ;;
    esac
}
show_status() {
    local manager file name dir
    manager="$(service_manager)"
    printf '\nXRDP status\nTarget user: %s\nHome: %s\nPackage manager: %s\nService backend: %s\n' "$target_user" "$target_home" "$(package_manager)" "$manager"
    for name in xrdp xorgxrdp; do if package_present "$name"; then echo "$name: installed"; else echo "$name: not confirmed installed"; fi; done
    case "$manager" in
        systemd) root systemctl --no-pager --full status xrdp.service xrdp-sesman.service || : ;;
        sysv) root service xrdp status || : ;;
        openrc) root rc-service xrdp status || : ;;
        runit) for name in xrdp xrdp-sesman; do dir="$(supervised_dir "$name")" && sv status "$dir"; done ;;
    esac
    if command -v ps >/dev/null; then ps -eo user,pid,args | grep -E '[x]rdp(-sesman)?([[:space:]]|$)' || :; fi
    if [ -x /usr/share/xrdp/xrdp-chkpriv ]; then
        echo 'Packaged XRDP privilege/configuration check:'
        root /usr/share/xrdp/xrdp-chkpriv || echo 'The packaged privilege check reported a problem; review its output.'
    fi
    echo 'Session file:'; as_target cat -- "$xsession_path" 2>/dev/null || echo '(not configured/readable)'
    echo 'Runtime socket directory:'; root ls -ld /run/xrdp /run/xrdp/sockdir 2>/dev/null || :
    if command -v ss >/dev/null; then
        echo 'TCP listener on default RDP port 3389 (custom ports may differ):'
        ss -ltn '( sport = :3389 )' || :
    fi
}
show_logs() {
    local file found=0
    for file in /var/log/xrdp.log /var/log/xrdp-sesman.log; do
        if root test -f "$file"; then printf '\n--- %s ---\n' "$file";root tail -n 80 -- "$file" || return 1;found=1;fi
    done
    if [ "$found" = 0 ] && [ -d /run/systemd/system ] && command -v journalctl >/dev/null; then
        root journalctl -u xrdp -u xrdp-sesman -n 100 --no-pager
    elif [ "$found" = 0 ]; then echo 'No standard XRDP logs found yet.'; fi
}
restore_xsession() {
    command -v python3 >/dev/null || { ensure_packages python3 || return 1; }
    echo "Restore the latest JS-Forge .xsession backup for $target_user; the current file is backed up first."
    confirm 'Restore this user session file?' || return 1
    session_helper restore
}
firewall_rule() {
    command -v ufw >/dev/null || { echo 'UFW is not installed. No firewall changes.'; return 1; }
    echo 'Add an incoming allow rule for TCP 3389 from all sources. UFW will NOT be enabled or reset.'
    echo 'For restricted source networks or a custom XRDP port, use your firewall controller instead.'
    confirm 'Add this explicit UFW rule?' || return 1
    root ufw allow 3389/tcp
}
main() {
    local selected rc
    if ! set_target "${1:-${SUDO_USER:-$(id -un)}}"; then
        echo 'Choose the account whose XRDP session should be configured.'
        read -r -p 'Target account: ' selected || return 1
        set_target "$selected" || return 1
    fi
    while :; do
        printf '\033[H\033[2JJS-Forge: XRDP Server\n\nTarget: %s | home: %s\n' "$target_user" "$target_home"
        echo 'No distro whitelist. Opening this menu does not change services or configuration.'
        cursor_menu 'Select an action:' selected 'Install / repair XRDP' 'Start and enable XRDP' 'Stop and disable XRDP' 'Set XRDP desktop session (.xsession)' 'Restore previous .xsession' 'Change target user' 'Repair SysV runtime / legacy startup' 'Check XRDP status' 'View XRDP logs' 'Optional UFW rule (TCP 3389)' 'Exit' || return 0
        rc=0
        case "$selected" in
            'Install / repair XRDP') install_xrdp || rc=$? ;;
            'Start and enable XRDP') start_xrdp_service || rc=$? ;;
            'Stop and disable XRDP') stop_xrdp_service || rc=$? ;;
            'Set XRDP desktop session (.xsession)') choose_desktop_session || rc=$? ;;
            'Restore previous .xsession') restore_xsession || rc=$? ;;
            'Change target user') change_target || rc=$? ;;
            'Repair SysV runtime / legacy startup') repair_sysv || rc=$? ;;
            'Check XRDP status') show_status || rc=$? ;;
            'View XRDP logs') show_logs || rc=$? ;;
            'Optional UFW rule (TCP 3389)') firewall_rule || rc=$? ;;
            *) return 0 ;;
        esac
        [ "$rc" = 0 ] || echo 'Action failed or was cancelled. Review the output above; no later automatic step was run.'
        pause_screen
    done
}
main "$@"