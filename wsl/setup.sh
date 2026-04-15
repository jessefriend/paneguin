#!/usr/bin/env bash
set -euo pipefail

DESKTOP_ENV="${DESKTOP_ENV:-kde}"
LINUX_USER="${LINUX_USER:-}"
PORT="${PORT:-3390}"
INSTALL_XFCE_FALLBACK="${INSTALL_XFCE_FALLBACK:-0}"
CONFIGURE_CHROME_INTEGRATION="${CONFIGURE_CHROME_INTEGRATION:-0}"
RESTRICT_XRDP_TO_WINDOWS_HOST="${RESTRICT_XRDP_TO_WINDOWS_HOST:-0}"

if [[ -z "${LINUX_USER}" ]]; then
  echo "LINUX_USER is required"
  exit 1
fi

source /etc/os-release

pm=""
case "${ID:-}" in
  ubuntu|debian) pm="apt" ;;
  fedora) pm="dnf" ;;
  opensuse-tumbleweed|opensuse-leap|opensuse) pm="zypper" ;;
  *)
    echo "Unsupported distro for this installer: ${ID:-unknown}"
    exit 1
    ;;
esac

install_pkgs() {
  case "$pm" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      if [[ "${apt_refreshed:-0}" != "1" ]]; then
        apt-get update
        apt_refreshed=1
      fi
      apt-get install -y "$@"
      ;;
    dnf)
      dnf install -y "$@"
      ;;
    zypper)
      if [[ "${zypper_refreshed:-0}" != "1" ]]; then
        zypper --non-interactive refresh
        zypper_refreshed=1
      fi
      zypper --non-interactive install "$@"
      ;;
  esac
}

install_candidate_sets() {
  local label="$1"
  shift

  local candidate
  local -a candidate_pkgs=()
  for candidate in "$@"; do
    read -r -a candidate_pkgs <<< "${candidate}"
    if install_pkgs "${candidate_pkgs[@]}"; then
      return 0
    fi

    echo "Tried ${label} candidate and it failed: ${candidate}"
  done

  echo "Failed to install ${label}."
  return 1
}

require_commands() {
  local label="$1"
  shift

  local -a missing=()
  local command_name
  for command_name in "$@"; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
      missing+=("${command_name}")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "Missing ${label}: ${missing[*]}"
    return 1
  fi
}

require_any_commands() {
  local label="$1"
  shift

  local command_name
  for command_name in "$@"; do
    if command -v "${command_name}" >/dev/null 2>&1; then
      return 0
    fi
  done

  echo "Missing ${label}: $*"
  return 1
}

common_packages=()
desktop_install_candidates=()
fallback_install_candidates=()
common_required_commands=(xrdp xauth)
desktop_required_commands=()
fallback_required_commands=()
session_command=""
desktop_name=""

case "$pm" in
  apt)
    common_packages=(xrdp xorgxrdp xorg xauth dbus-x11 desktop-file-utils xdg-utils curl wget iptables)
    case "${DESKTOP_ENV}" in
      kde)
        desktop_install_candidates=("plasma-desktop plasma-workspace konsole dolphin systemsettings")
        desktop_required_commands=(startplasma-x11 plasmashell)
        if [[ "${INSTALL_XFCE_FALLBACK}" == "1" ]]; then
          fallback_install_candidates=("xfce4 xfce4-goodies xfce4-terminal thunar")
          fallback_required_commands=(startxfce4 xfce4-session)
        fi
        session_command="startplasma-x11"
        desktop_name="KDE"
        ;;
      xfce)
        desktop_install_candidates=("xfce4 xfce4-goodies xfce4-terminal thunar")
        desktop_required_commands=(startxfce4 xfce4-session)
        session_command="startxfce4"
        desktop_name="XFCE"
        ;;
      mate)
        desktop_install_candidates=("mate-desktop-environment-core mate-terminal caja")
        desktop_required_commands=(mate-session marco mate-panel)
        session_command="mate-session"
        desktop_name="MATE"
        ;;
      lxqt)
        desktop_install_candidates=("lxqt openbox qterminal pcmanfm-qt")
        desktop_required_commands=(startlxqt openbox lxqt-panel)
        session_command="startlxqt"
        desktop_name="LXQt"
        ;;
      *)
        echo "Unsupported DESKTOP_ENV: ${DESKTOP_ENV}"; exit 1 ;;
    esac
    ;;
  dnf)
    common_packages=(xrdp xorgxrdp xauth dbus-x11 xdg-utils curl wget iptables xorg-x11-server-Xorg)
    case "${DESKTOP_ENV}" in
      kde)
        desktop_install_candidates=("@kde-desktop-environment konsole dolphin" "@kde-desktop konsole dolphin")
        desktop_required_commands=(startplasma-x11 plasmashell)
        if [[ "${INSTALL_XFCE_FALLBACK}" == "1" ]]; then
          fallback_install_candidates=("@xfce-desktop-environment xfce4-terminal Thunar" "@xfce-desktop xfce4-terminal Thunar")
          fallback_required_commands=(startxfce4 xfce4-session)
        fi
        session_command="startplasma-x11"
        desktop_name="KDE"
        ;;
      xfce)
        desktop_install_candidates=("@xfce-desktop-environment xfce4-terminal Thunar" "@xfce-desktop xfce4-terminal Thunar" "xfce4-session xfce4-panel xfdesktop xfwm4 xfconf exo tumbler Thunar xfce4-terminal mousepad")
        desktop_required_commands=(startxfce4 xfce4-session)
        session_command="startxfce4"
        desktop_name="XFCE"
        ;;
      mate)
        desktop_install_candidates=("@mate-desktop-environment mate-terminal caja" "mate-session-manager mate-panel marco mate-settings-daemon mate-control-center mate-terminal caja")
        desktop_required_commands=(mate-session marco mate-panel)
        session_command="mate-session"
        desktop_name="MATE"
        ;;
      lxqt)
        desktop_install_candidates=("@lxqt-desktop-environment openbox qterminal pcmanfm-qt" "lxqt openbox qterminal pcmanfm-qt")
        desktop_required_commands=(startlxqt openbox lxqt-panel)
        session_command="startlxqt"
        desktop_name="LXQt"
        ;;
      *)
        echo "Unsupported DESKTOP_ENV: ${DESKTOP_ENV}"; exit 1 ;;
    esac
    ;;
  zypper)
    common_packages=(xrdp xorgxrdp xauth dbus-1 xdg-utils curl wget iptables)
    case "${DESKTOP_ENV}" in
      kde)
        desktop_install_candidates=("patterns-kde-kde_plasma konsole dolphin6" "patterns-kde-kde konsole dolphin6" "patterns-kde-kde konsole dolphin")
        desktop_required_commands=(startplasma-x11 plasmashell)
        if [[ "${INSTALL_XFCE_FALLBACK}" == "1" ]]; then
          fallback_install_candidates=("patterns-xfce-xfce xfce4-terminal Thunar")
          fallback_required_commands=(startxfce4 xfce4-session)
        fi
        session_command="startplasma-x11"
        desktop_name="KDE"
        ;;
      xfce)
        desktop_install_candidates=("patterns-xfce-xfce xfce4-terminal Thunar")
        desktop_required_commands=(startxfce4 xfce4-session)
        session_command="startxfce4"
        desktop_name="XFCE"
        ;;
      mate)
        desktop_install_candidates=("patterns-mate-mate mate-terminal caja" "mate-session-manager mate-panel marco mate-terminal caja")
        desktop_required_commands=(mate-session marco mate-panel)
        session_command="mate-session"
        desktop_name="MATE"
        ;;
      lxqt)
        desktop_install_candidates=("patterns-lxqt-lxqt openbox qterminal pcmanfm-qt")
        desktop_required_commands=(startlxqt openbox lxqt-panel)
        session_command="startlxqt"
        desktop_name="LXQt"
        ;;
      *)
        echo "Unsupported DESKTOP_ENV: ${DESKTOP_ENV}"; exit 1 ;;
    esac
    ;;
esac

install_pkgs "${common_packages[@]}"
install_candidate_sets "${desktop_name} desktop" "${desktop_install_candidates[@]}"
if [[ "${#fallback_install_candidates[@]}" -gt 0 ]]; then
  install_candidate_sets "XFCE fallback desktop" "${fallback_install_candidates[@]}"
fi

require_commands "common XRDP/X11 commands" "${common_required_commands[@]}"
require_any_commands "DBus session helper" dbus-run-session dbus-launch
require_commands "${desktop_name} session commands" "${desktop_required_commands[@]}"
if [[ "${#fallback_required_commands[@]}" -gt 0 ]]; then
  require_commands "XFCE fallback session commands" "${fallback_required_commands[@]}"
fi

home_dir="$(getent passwd "${LINUX_USER}" | cut -d: -f6)"
if [[ -z "${home_dir}" ]]; then
  echo "Could not determine home directory for ${LINUX_USER}"
  exit 1
fi

install -d -m 0755 -o "${LINUX_USER}" -g "${LINUX_USER}" "${home_dir}/bin"
install -d -m 0755 -o "${LINUX_USER}" -g "${LINUX_USER}" "${home_dir}/.local/share/applications"

cat > "${home_dir}/bin/wsl-session-start" <<EOF
#!/bin/sh
set -eu

LOG_FILE="${home_dir}/.paneguin-session.log"
echo "---- NEW SESSION ----" > "\${LOG_FILE}"

# Clean up stale X session locks that cause a blue screen on reconnect
rm -f /tmp/.X10-lock /tmp/.X11-unix/X10 2>/dev/null || true

uid_val=\$(id -u)
runtime_dir="/run/user/\${uid_val}"
if [ ! -d "\${runtime_dir}" ] || [ ! -w "\${runtime_dir}" ]; then
  runtime_dir="/tmp/paneguin-runtime-\${uid_val}"
  mkdir -p "\${runtime_dir}" 2>/dev/null || true
  chmod 700 "\${runtime_dir}" 2>/dev/null || true
fi

export XDG_RUNTIME_DIR="\${runtime_dir}"
export XDG_SESSION_TYPE="x11"
export GDK_BACKEND="x11"
export QT_QPA_PLATFORM="xcb"

case "${DESKTOP_ENV}" in
  kde)
    export DESKTOP_SESSION="plasma"
    export XDG_CURRENT_DESKTOP="KDE"
    export XDG_SESSION_DESKTOP="KDE"
    export KDE_FULL_SESSION="true"
    ;;
  xfce)
    export DESKTOP_SESSION="xfce"
    export XDG_CURRENT_DESKTOP="XFCE"
    export XDG_SESSION_DESKTOP="XFCE"
    ;;
  mate)
    export DESKTOP_SESSION="mate"
    export XDG_CURRENT_DESKTOP="MATE"
    export XDG_SESSION_DESKTOP="MATE"
    ;;
  lxqt)
    export DESKTOP_SESSION="lxqt"
    export XDG_CURRENT_DESKTOP="LXQt"
    export XDG_SESSION_DESKTOP="LXQt"
    ;;
esac

unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER

echo "XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR}" >>"\${LOG_FILE}"
echo "DESKTOP_SESSION=\${DESKTOP_SESSION:-}" >>"\${LOG_FILE}"
echo "XDG_CURRENT_DESKTOP=\${XDG_CURRENT_DESKTOP:-}" >>"\${LOG_FILE}"

if command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session -- ${session_command} >>"\${LOG_FILE}" 2>&1
fi

exec dbus-launch --exit-with-session ${session_command} >>"\${LOG_FILE}" 2>&1
EOF
chown "${LINUX_USER}:${LINUX_USER}" "${home_dir}/bin/wsl-session-start"
chmod +x "${home_dir}/bin/wsl-session-start"

cat > "${home_dir}/.xsession" <<EOF
#!/bin/sh
exec ${home_dir}/bin/wsl-session-start
EOF
chown "${LINUX_USER}:${LINUX_USER}" "${home_dir}/.xsession"
chmod +x "${home_dir}/.xsession"

cat > /etc/xrdp/startwm.sh <<'EOF'
#!/bin/sh
if test -r /etc/profile; then
    . /etc/profile
fi

unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER

exec /bin/sh ~/.xsession
EOF
chmod +x /etc/xrdp/startwm.sh

if grep -q '^port=' /etc/xrdp/xrdp.ini; then
  sed -i "s/^port=.*/port=${PORT}/" /etc/xrdp/xrdp.ini
fi

cat > /etc/paneguin.conf <<EOF
XRDP_PORT=${PORT}
RESTRICT_XRDP_TO_WINDOWS_HOST=${RESTRICT_XRDP_TO_WINDOWS_HOST}
EOF
chmod 0644 /etc/paneguin.conf

cat > /usr/local/sbin/paneguin-ensure-xrdp <<'EOF'
#!/bin/sh
set -eu

CONFIG_FILE="/etc/paneguin.conf"
XRDP_PORT=3390
RESTRICT_XRDP_TO_WINDOWS_HOST=0
HOST_IPS=""

if [ -r "${CONFIG_FILE}" ]; then
  . "${CONFIG_FILE}"
fi

append_host_ip() {
  candidate="$1"
  case "${candidate}" in
    ""|127.*|0.0.0.0)
      return 0
      ;;
  esac

  echo "${candidate}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || return 0

  case "
${HOST_IPS}
" in
    *"
${candidate}
"*)
      ;;
    *)
      HOST_IPS="${HOST_IPS}${HOST_IPS:+
}${candidate}"
      ;;
  esac
}

if command -v ip >/dev/null 2>&1; then
  append_host_ip "$(ip route show default 2>/dev/null | awk 'NR==1 {print $3}')"
fi

if [ -r /etc/resolv.conf ]; then
  while IFS= read -r nameserver; do
    append_host_ip "${nameserver}"
  done <<EOF_RESOLV
$(sed -n 's/^nameserver[[:space:]]\+//p' /etc/resolv.conf 2>/dev/null)
EOF_RESOLV
fi

apply_xrdp_guard() {
  if ! command -v iptables >/dev/null 2>&1; then
    echo "XRDP host-only restriction was requested, but iptables is not available."
    return 1
  fi

  if [ -z "${HOST_IPS}" ]; then
    echo "XRDP host-only restriction was requested, but the Windows host IP could not be detected."
    return 1
  fi

  CHAIN="WSL_XRDP_GUARD"
  iptables -N "${CHAIN}" 2>/dev/null || true
  iptables -F "${CHAIN}"
  iptables -C INPUT -p tcp --dport "${XRDP_PORT}" -j "${CHAIN}" 2>/dev/null || iptables -I INPUT 1 -p tcp --dport "${XRDP_PORT}" -j "${CHAIN}"
  iptables -A "${CHAIN}" -i lo -j ACCEPT

  for host_ip in ${HOST_IPS}; do
    iptables -A "${CHAIN}" -s "${host_ip}" -p tcp --dport "${XRDP_PORT}" -j ACCEPT
  done

  iptables -A "${CHAIN}" -p tcp --dport "${XRDP_PORT}" -j DROP
}

if [ "${RESTRICT_XRDP_TO_WINDOWS_HOST}" = "1" ]; then
  apply_xrdp_guard
fi

if command -v pgrep >/dev/null 2>&1 && pgrep -x xrdp >/dev/null 2>&1; then
  :
else
  service xrdp start >/dev/null 2>&1 || service xrdp restart >/dev/null 2>&1 || {
    echo "Failed to start xrdp."
    exit 1
  }
fi

if [ "${RESTRICT_XRDP_TO_WINDOWS_HOST}" = "1" ]; then
  echo "XRDP restricted to Windows host IPs:"
  printf '%s\n' "${HOST_IPS}"
fi
EOF
chmod 0755 /usr/local/sbin/paneguin-ensure-xrdp

printf '%s ALL=(root) NOPASSWD: /usr/local/sbin/paneguin-ensure-xrdp\n' "${LINUX_USER}" > /etc/sudoers.d/paneguin-ensure-xrdp
chmod 0440 /etc/sudoers.d/paneguin-ensure-xrdp

cat > "${home_dir}/bin/paneguin-repair" <<EOF
#!/bin/sh
set -eu

uid_val=\$(id -u)
runtime_dir="/run/user/\${uid_val}"
if [ ! -d "\${runtime_dir}" ] || [ ! -w "\${runtime_dir}" ]; then
  runtime_dir="/tmp/paneguin-runtime-\${uid_val}"
  mkdir -p "\${runtime_dir}" 2>/dev/null || true
  chmod 700 "\${runtime_dir}" 2>/dev/null || true
fi

pkill -f startplasma || true
pkill -f plasmashell || true
pkill -f kwin || true
pkill -f kglobalaccel || true
pkill -f xsettingsd || true
pkill -f polkit-kde-authentication-agent || true
pkill -f xfce4-session || true

# Remove stale X session locks that cause a blue screen on reconnect
rm -f /tmp/.X10-lock /tmp/.X11-unix/X10 2>/dev/null || true

if [ -x /usr/local/sbin/paneguin-ensure-xrdp ]; then
  sudo -n /usr/local/sbin/paneguin-ensure-xrdp || true
else
  sudo service xrdp restart || sudo service xrdp start || true
fi

echo "Repaired XRDP/session state."
echo "If it still fails, inspect:"
echo "  tail -n 100 ${home_dir}/.paneguin-session.log"
EOF
chown "${LINUX_USER}:${LINUX_USER}" "${home_dir}/bin/paneguin-repair"
chmod +x "${home_dir}/bin/paneguin-repair"


# Fix xrdp TLS key permissions so xrdp can read key.pem on startup.
# Without this the first connection attempt fails with "Permission denied" on key.pem,
# causing a disconnect (RDP error 0x904) before mstsc retries with standard RDP security.
if getent group ssl-cert >/dev/null 2>&1; then
  usermod -aG ssl-cert xrdp 2>/dev/null || true
  chown root:ssl-cert /etc/xrdp/key.pem 2>/dev/null || true
  chmod 640 /etc/xrdp/key.pem 2>/dev/null || true
else
  chown root:xrdp /etc/xrdp/key.pem 2>/dev/null || true
  chmod 640 /etc/xrdp/key.pem 2>/dev/null || true
fi

if [[ -f /etc/xrdp/sesman.ini ]]; then
  sed -i 's/^[#[:space:]]*KillDisconnected=.*/KillDisconnected=false/' /etc/xrdp/sesman.ini || true
  if grep -q '^[#[:space:]]*DisconnectedTimeLimit=' /etc/xrdp/sesman.ini; then
    sed -i 's/^[#[:space:]]*DisconnectedTimeLimit=.*/DisconnectedTimeLimit=0/' /etc/xrdp/sesman.ini || true
  else
    printf '\n[Sessions]\nDisconnectedTimeLimit=0\n' >> /etc/xrdp/sesman.ini
  fi
  if grep -q '^[#[:space:]]*IdleTimeLimit=' /etc/xrdp/sesman.ini; then
    sed -i 's/^[#[:space:]]*IdleTimeLimit=.*/IdleTimeLimit=0/' /etc/xrdp/sesman.ini || true
  else
    printf 'IdleTimeLimit=0\n' >> /etc/xrdp/sesman.ini
  fi
fi

chrome_integration_configured=0
chrome_integration_requested=0

if [[ "${CONFIGURE_CHROME_INTEGRATION}" == "1" ]]; then
  chrome_integration_requested=1
  if command -v google-chrome-stable >/dev/null 2>&1; then
    install -d -m 0755 -o "${LINUX_USER}" -g "${LINUX_USER}" "${home_dir}/.chrome-wsl"
    cat > "${home_dir}/bin/google-chrome-wsl" <<EOF
#!/bin/sh
exec /usr/bin/google-chrome-stable \
  --user-data-dir=${home_dir}/.chrome-wsl \
  --disable-gpu \
  --disable-dev-shm-usage \
  --disable-background-networking \
  --disable-component-update \
  --disable-features=MediaRouter \
  "\$@"
EOF
    chown "${LINUX_USER}:${LINUX_USER}" "${home_dir}/bin/google-chrome-wsl"
    chmod +x "${home_dir}/bin/google-chrome-wsl"

    cat > "${home_dir}/.local/share/applications/google-chrome-wsl.desktop" <<EOF
[Desktop Entry]
Version=1.0
Name=Google Chrome WSL
GenericName=Web Browser
Comment=Access the Internet
Exec=${home_dir}/bin/google-chrome-wsl %U
Terminal=false
Icon=google-chrome
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
StartupNotify=true
StartupWMClass=Google-chrome
EOF
    chown "${LINUX_USER}:${LINUX_USER}" "${home_dir}/.local/share/applications/google-chrome-wsl.desktop"
    chmod +x "${home_dir}/.local/share/applications/google-chrome-wsl.desktop"

    if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database "${home_dir}/.local/share/applications" || true
    fi

    su - "${LINUX_USER}" -c "xdg-settings set default-web-browser google-chrome-wsl.desktop" || true
    su - "${LINUX_USER}" -c "xdg-mime default google-chrome-wsl.desktop x-scheme-handler/http" || true
    su - "${LINUX_USER}" -c "xdg-mime default google-chrome-wsl.desktop x-scheme-handler/https" || true
    su - "${LINUX_USER}" -c "xdg-mime default google-chrome-wsl.desktop text/html" || true

    if command -v kbuildsycoca5 >/dev/null 2>&1; then
      su - "${LINUX_USER}" -c "kbuildsycoca5" || true
    fi

    chrome_integration_configured=1
  else
    echo "Chrome integration was requested, but google-chrome-stable is not installed in WSL. Skipping browser integration."
  fi
fi

service dbus start || true
/usr/local/sbin/paneguin-ensure-xrdp

echo ""
echo "Installed ${desktop_name} on distro ${PRETTY_NAME} for user ${LINUX_USER}."
echo "XRDP configured on port ${PORT}."
if [[ "${DESKTOP_ENV}" == "kde" && "${INSTALL_XFCE_FALLBACK}" == "1" ]]; then
  echo "XFCE fallback installed for KDE session recovery."
fi
if [[ "${RESTRICT_XRDP_TO_WINDOWS_HOST}" == "1" ]]; then
  echo "XRDP host-only restriction is enabled."
fi
if [[ "${chrome_integration_configured}" == "1" ]]; then
  echo "Chrome integration configured for Paneguin."
elif [[ "${chrome_integration_requested}" == "1" ]]; then
  echo "Chrome integration was requested, but Chrome was not found in WSL."
fi
echo "Session log: ${home_dir}/.paneguin-session.log"
