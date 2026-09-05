FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt update -y && apt install --no-install-recommends -y xfce4 xfce4-goodies tigervnc-standalone-server novnc websockify sudo xterm init systemd snapd vim net-tools curl wget git tzdata openssh-server
RUN apt update -y && apt install -y dbus-x11 x11-utils x11-xserver-utils x11-apps
RUN apt install software-properties-common -y
RUN add-apt-repository ppa:mozillateam/ppa -y
RUN echo 'Package: *' >> /etc/apt/preferences.d/mozilla-firefox
RUN echo 'Pin: release o=LP-PPA-mozillateam' >> /etc/apt/preferences.d/mozilla-firefox
RUN echo 'Pin-Priority: 1001' >> /etc/apt/preferences.d/mozilla-firefox
RUN echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:jammy";' | tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox
RUN apt update -y && apt install -y firefox
RUN apt update -y && apt install -y xubuntu-icon-theme
RUN touch /root/.Xauthority

# ---- Performance tuning: reduce VNC/noVNC lag on low-bandwidth links (e.g. Railway) ----

# Pre-seed Xfce settings BEFORE first login so the compositor, window-manager
# shadows/animations, and DPMS/power-manager blanking are already off on first
# session start (avoids a laggy "effects on -> effects off" flash and avoids
# racing xfconf-query against a not-yet-running settings daemon).
RUN mkdir -p /root/.config/xfce4/xfconf/xfce-perchannel-xml
RUN printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<channel name="xfwm4" version="1.0">' \
    '  <property name="general" type="empty">' \
    '    <property name="use_compositing" type="bool" value="false"/>' \
    '    <property name="show_frame_shadow" type="bool" value="false"/>' \
    '    <property name="show_popup_shadow" type="bool" value="false"/>' \
    '    <property name="show_dock_shadow" type="bool" value="false"/>' \
    '    <property name="box_move" type="bool" value="false"/>' \
    '    <property name="box_resize" type="bool" value="false"/>' \
    '    <property name="frame_opacity" type="int" value="100"/>' \
    '    <property name="popup_opacity" type="int" value="100"/>' \
    '    <property name="move_opacity" type="int" value="100"/>' \
    '    <property name="resize_opacity" type="int" value="100"/>' \
    '    <property name="wrap_workspaces" type="bool" value="false"/>' \
    '    <property name="workspace_count" type="int" value="1"/>' \
    '    <property name="easy_click" type="string" value="Alt"/>' \
    '  </property>' \
    '</channel>' \
    > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
RUN printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<channel name="xsettings" version="1.0">' \
    '  <property name="Gtk" type="empty">' \
    '    <property name="EnableAnimations" type="bool" value="false"/>' \
    '  </property>' \
    '  <property name="Net" type="empty">' \
    '    <property name="ThemeName" type="string" value="Adwaita"/>' \
    '  </property>' \
    '</channel>' \
    > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
RUN printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<channel name="xfce4-power-manager" version="1.0">' \
    '  <property name="xfce4-power-manager" type="empty">' \
    '    <property name="dpms-enabled" type="bool" value="false"/>' \
    '    <property name="dpms-on-ac-sleep" type="uint" value="0"/>' \
    '    <property name="dpms-on-ac-off" type="uint" value="0"/>' \
    '    <property name="blank-on-ac" type="int" value="0"/>' \
    '    <property name="lock-screen-suspend-hibernate" type="bool" value="false"/>' \
    '  </property>' \
    '</channel>' \
    > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml

# Custom vncserver xstartup: disables X-level screen blanking/DPMS/screensaver
# (these otherwise trigger full-screen redraws that eat VNC bandwidth) and
# starts the Xfce session with the pre-seeded low-effects settings above.
RUN mkdir -p /root/.vnc
RUN printf '%s\n' \
    '#!/bin/bash' \
    'unset SESSION_MANAGER' \
    'unset DBUS_SESSION_BUS_ADDRESS' \
    '' \
    'xrdb "$HOME/.Xresources" 2>/dev/null' \
    '' \
    '# Disable screen blanking, DPMS and the screensaver at the X server level.' \
    'xset s off' \
    'xset s noblank' \
    'xset -dpms' \
    '' \
    'exec startxfce4' \
    > /root/.vnc/xstartup
RUN chmod +x /root/.vnc/xstartup

# ---- SSH access (terminal control from Termux etc, key-auth only) ----
# Root login is allowed but ONLY via SSH key - password auth is fully disabled
# so this is safe to expose on the public internet via a Railway TCP proxy.
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh
RUN printf '%s\n' \
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHSNDvZGVGUi1EsTjAXaQ47yiILWIm8CaICvBqhiZPj7 alix@termux-railway-vps' \
    > /root/.ssh/authorized_keys
RUN chmod 600 /root/.ssh/authorized_keys
RUN mkdir -p /run/sshd
RUN printf '%s\n' \
    'PermitRootLogin prohibit-password' \
    'PasswordAuthentication no' \
    'KbdInteractiveAuthentication no' \
    'PubkeyAuthentication yes' \
    'X11Forwarding no' \
    'AllowTcpForwarding yes' \
    >> /etc/ssh/sshd_config

EXPOSE 5901
EXPOSE 6080
EXPOSE 22
CMD bash -c "/usr/sbin/sshd && vncserver -localhost no -SecurityTypes None -depth 16 -geometry 1024x768 --I-KNOW-THIS-IS-INSECURE && openssl req -new -subj "/C=JP" -x509 -days 365 -nodes -out self.pem -keyout self.pem && websockify -D --web=/usr/share/novnc/ --cert=self.pem 6080 localhost:5901 && tail -f /dev/null"
