#!/bin/bash
set -e

if [ ! -f "logo.png" ]; then
    echo "ОШИБКА: Файл logo.png не найден!"
    exit 1
fi

OS_NAME="KoolBoobaOS"
WORK_DIR="koolbooba_workspace"
CHROOT_DIR="$WORK_DIR/chroot"
IMAGE_DIR="$WORK_DIR/image"

echo "=== 1. Подготовка папок ==="
rm -rf $WORK_DIR
mkdir -p $CHROOT_DIR
mkdir -p $IMAGE_DIR/live
mkdir -p $IMAGE_DIR/boot/grub

echo "=== 2. Скачивание базы Debian ==="
sudo debootstrap --arch=amd64 stable $CHROOT_DIR http://deb.debian.org/debian/

# Монтируем системные директории для корректной установки пакетов
sudo mount -t proc /proc $CHROOT_DIR/proc
sudo mount -t sysfs /sys $CHROOT_DIR/sys
sudo mount -o bind /dev $CHROOT_DIR/dev

sudo mkdir -p $CHROOT_DIR/usr/share/pixmaps/
sudo cp logo.png $CHROOT_DIR/usr/share/pixmaps/koolbooba-logo.png

echo "=== 3. Настройка системы внутри chroot ==="
cat <<EOF | sudo chroot $CHROOT_DIR /bin/bash
# Отключаем интерактивные вопросы при установке
export DEBIAN_FRONTEND=noninteractive

echo "deb http://deb.debian.org/debian stable main contrib non-free-firmware" > /etc/apt/sources.list
apt-get update

# Базовые утилиты
apt-get install -y --no-install-recommends linux-image-amd64 live-boot systemd-sysv sudo wget unzip

# XFCE4 и графика
apt-get install -y --no-install-recommends xorg xfce4 xfce4-whiskermenu-plugin xfce4-terminal lightdm thunar

# Установщик системы
apt-get install -y --no-install-recommends calamares calamares-settings-debian

# Брендинг
echo "$OS_NAME" > /etc/hostname
cat <<EOR > /etc/os-release
PRETTY_NAME="$OS_NAME 1.0 (Windows 7 Edition)"
NAME="$OS_NAME"
VERSION_ID="1.0"
ID=koolbooba
EOR

# Пользователь
useradd -m -s /bin/bash oleg
echo "oleg:oleg" | chpasswd
usermod -aG sudo oleg

# Автологин
sed -i 's/^#autologin-user=.*/autologin-user=oleg/' /etc/lightdm/lightdm.conf
sed -i 's/^#autologin-user-timeout=.*/autologin-user-timeout=0/' /etc/lightdm/lightdm.conf

# Темы Windows 7
mkdir -p /usr/share/themes /usr/share/icons
wget -q https://github.com/B00merang-Project/Windows-7/archive/master.zip -O /tmp/win7_theme.zip
unzip -q /tmp/win7_theme.zip -d /usr/share/themes/
wget -q https://github.com/B00merang-Project/Windows-7-Icons/archive/master.zip -O /tmp/win7_icons.zip
unzip -q /tmp/win7_icons.zip -d /usr/share/icons/

# Скрипт стилизации (Windows 7)
mkdir -p /etc/skel/.config/autostart
mkdir -p /etc/skel/Desktop

cp /usr/share/applications/calamares.desktop /etc/skel/Desktop/
chmod +x /etc/skel/Desktop/calamares.desktop

cat <<EOS > /etc/skel/.config/win7-setup.sh
#!/bin/bash
xfconf-query -c xsettings -p /Net/ThemeName -s "Windows-7-master"
xfconf-query -c xfwm4 -p /general/theme -s "Windows-7-master"
xfconf-query -c xsettings -p /Net/IconThemeName -s "Windows-7-Icons-master"
xfconf-query -c xfce4-panel -p /panels/panel-1/position -s "p=10;x=0;y=0"
xfconf-query -c xfce4-panel -p /panels/panel-1/size -s 40
xfconf-query -c xfce4-panel -p /plugins/plugin-1/button-icon -s /usr/share/pixmaps/koolbooba-logo.png
xfconf-query -c xfce4-panel -p /plugins/plugin-1/button-title -s "KoolBooba"
EOS
chmod +x /etc/skel/.config/win7-setup.sh

cat <<EOA > /etc/skel/.config/autostart/win7-setup.desktop
[Desktop Entry]
Type=Application
Name=Win7Setup
Exec=/etc/skel/.config/win7-setup.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOA

apt-get clean
rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*
EOF

echo "=== 4. Размонтирование директорий ==="
sudo umount $CHROOT_DIR/dev
sudo umount $CHROOT_DIR/sys
sudo umount $CHROOT_DIR/proc

echo "=== 5. Создание файлов загрузки ==="
cp $CHROOT_DIR/boot/vmlinuz-* $IMAGE_DIR/live/vmlinuz
cp $CHROOT_DIR/boot/initrd.img-* $IMAGE_DIR/live/initrd.img

sudo mksquashfs $CHROOT_DIR $IMAGE_DIR/live/filesystem.squashfs -e boot

cat <<EOF > $IMAGE_DIR/boot/grub/grub.cfg
set default=0
set timeout=5
menuentry "Start $OS_NAME" {
    linux /live/vmlinuz boot=live quiet splash
    initrd /live/initrd.img
}
EOF

echo "=== 6. Сборка ISO образа ==="
grub-mkrescue -o koolboobaOS.iso $IMAGE_DIR
echo "УСПЕХ!"
