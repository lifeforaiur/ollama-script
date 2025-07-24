#!/bin/bash

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本"
  exit 1
fi

# 设置目标用户
TARGET_USER="ubuntu-xrdp"

# 检查用户是否存在
if ! id "$TARGET_USER" &>/dev/null; then
    echo "错误：用户 $TARGET_USER 不存在，请先使用 'sudo useradd -m ubuntu-xrdp' 创建用户"
    exit 1
fi

# 更新系统
echo "正在更新系统..."
apt update && apt upgrade -y

# 安装桌面环境（如果尚未安装）
echo "正在安装 GNOME 桌面环境..."
apt install -y ubuntu-desktop

# 安装 XRDP
echo "正在安装 XRDP..."
apt install -y xrdp

# 启用 XRDP 服务
systemctl enable xrdp
systemctl restart xrdp

# 解决黑屏问题
echo "正在配置 XRDP 以解决黑屏问题..."

# 创建 .xsession 文件（针对 ubuntu-xrdp 用户）
cat > /home/$TARGET_USER/.xsession << EOF
#!/bin/sh
# 设置 GNOME 作为默认会话
export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=ubuntu:GNOME
exec /usr/bin/gnome-session
EOF

# 确保权限正确
chown $TARGET_USER:$TARGET_USER /home/$TARGET_USER/.xsession
chmod +x /home/$TARGET_USER/.xsession

# 为 ubuntu-xrdp 用户设置密码（如果尚未设置）
if ! passwd -S $TARGET_USER | grep -q "P"; then
    echo "设置 $TARGET_USER 用户的密码..."
    passwd $TARGET_USER
fi

# 修复 polkit 策略
echo "正在修复 polkit 配置..."
cat > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla << EOF
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

# 针对远程桌面用户的特殊策略
cat > /etc/polkit-1/localauthority/50-local.d/46-allow-xrdp-user.pkla << EOF
[Allow XRDP User]
Identity=unix-user:$TARGET_USER
Action=org.freedesktop.login1.reboot;org.freedesktop.login1.power-off;org.freedesktop.login1.suspend;org.freedesktop.login1.hibernate
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF

# 配置 XRDP 使用自定义脚本
echo "正在配置 XRDP 以使用自定义脚本..."
cat > /etc/xrdp/startwm.sh << EOF
#!/bin/sh

if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

# 使用 .xsession 文件
if [ -f ~/.xsession ]; then
  . ~/.xsession
else
  # 否则默认启动 GNOME 会话
  export GNOME_SHELL_SESSION_MODE=ubuntu
  export XDG_SESSION_TYPE=x11
  export XDG_CURRENT_DESKTOP=ubuntu:GNOME
  exec /usr/bin/gnome-session
fi
EOF

# 确保脚本权限正确
chmod +x /etc/xrdp/startwm.sh

# 禁用 GNOME 的屏幕锁定，可能导致连接问题
echo "禁用屏幕锁定..."
sudo -u $TARGET_USER dbus-launch --exit-with-session gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
sudo -u $TARGET_USER dbus-launch --exit-with-session gsettings set org.gnome.desktop.lockdown disable-lock-screen true 2>/dev/null || true

# 添加用户到必要的组
usermod -a -G ssl-cert $TARGET_USER

# 确保用户有正确的组权限
usermod -a -G audio,video,cdrom,plugdev,netdev,lpadmin,scanner $TARGET_USER

# 更新 XRDP 配置以支持更好的颜色深度
sed -i 's/max_bpp=32/max_bpp=128/g' /etc/xrdp/xrdp.ini
sed -i 's/xserverbpp=24/xserverbpp=128/g' /etc/xrdp/xrdp.ini

# 创建 Xorg 配置目录（如果不存在）
mkdir -p /home/$TARGET_USER/.config

# 设置正确的所有权
chown -R $TARGET_USER:$TARGET_USER /home/$TARGET_USER/.config

# 创建 .Xauthority 文件
touch /home/$TARGET_USER/.Xauthority
chown $TARGET_USER:$TARGET_USER /home/$TARGET_USER/.Xauthority

# 创建一个自定义脚本来帮助修复会话问题
cat > /home/$TARGET_USER/.xsessionrc << EOF
#!/bin/bash
export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=ubuntu:GNOME
export XDG_CONFIG_DIRS=/etc/xdg/xdg-ubuntu:/etc/xdg
EOF

# 设置权限
chown $TARGET_USER:$TARGET_USER /home/$TARGET_USER/.xsessionrc
chmod +x /home/$TARGET_USER/.xsessionrc

# 重启 XRDP 服务
systemctl restart xrdp

# 配置防火墙（如果启用）
echo "配置防火墙..."
ufw allow 3389/tcp 2>/dev/null || true

echo "XRDP 安装和配置完成，现在您可以使用远程桌面客户端连接到此服务器。"
echo "连接地址：$(hostname -I | awk '{print $1}'):3389"
echo "用户名：$TARGET_USER"
echo ""
echo "如果仍然出现黑屏问题，请尝试以下操作："
echo "1. 重启服务器：sudo reboot"
echo "2. 确保使用了正确的用户名和密码"
echo "3. 检查日志文件：sudo cat /var/log/xrdp*.log"

# 可选：安装 XFCE4 桌面环境作为备选方案
echo ""
echo "是否同时安装 XFCE4 桌面环境作为备选方案？（推荐用于更稳定的远程会话）[y/n]"
read -r install_xfce

if [[ $install_xfce =~ ^[Yy]$ ]]; then
    echo "安装 XFCE4 桌面环境..."
    apt install -y xfce4 xfce4-goodies
    
    # 为 ubuntu-xrdp 用户配置 XFCE4
    echo "xfce4-session" > /home/$TARGET_USER/.xsession
    chown $TARGET_USER:$TARGET_USER /home/$TARGET_USER/.xsession
    
    echo ""
    echo "XFCE4 已安装完成。如果 GNOME 远程连接出现问题，可以通过编辑 ~/.xsession 文件切换桌面环境："
    echo "echo 'xfce4-session' > ~/.xsession  # 使用 XFCE4"
    echo "echo 'gnome-session' > ~/.xsession  # 使用 GNOME"
fi
