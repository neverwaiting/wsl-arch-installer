#!/bin/sh

set -e

[[ `whoami` = "root" ]] || echo "current user is not root!"

name="wintersun"
password="root"

USER_HOME="/home/$name"
USER_LOCAL_HOME="$USER_HOME/.local"
USER_CONFIG_HOME="$USER_HOME/.config"
MIRROR_GITHUB_URL_PREFIX="https://ghproxy.cn"
MIRROR_GITHUB_URL="$MIRROR_GITHUB_URL_PREFIX/https://github.com"
TEMP_PACKAGES_DIR="/tmp/packages"

pacman_install() {
  pacman --noconfirm --needed -S $@
}

aur_install() {
  [ -d "$TEMP_PACKAGES_DIR" ] || sudo -u "$name" mkdir -p "$TEMP_PACKAGES_DIR"
  for item in $@; do
    sudo -u "$name" git -C "$TEMP_PACKAGES_DIR" clone "https://aur.archlinux.org/${item}.git" && \
    sudo -u "$name" sed -iE 's#https://github\.com#https://ghproxy\.cn/&#g' "$TEMP_PACKAGES_DIR/$item/PKGBUILD" && \
    pushd "$TEMP_PACKAGES_DIR/$item" && \
    sudo -u "$name" GOPROXY="https://goproxy.cn" makepkg --noconfirm -si && \
    popd || echo -e "########## AUR: Install $item failed! ##########\n"
  done
}

yay_install() {
  sudo -u "$name" yay -S --noconfirm $@
}

git_install() {
  [ -d "$TEMP_PACKAGES_DIR" ] || sudo -u "$name" mkdir -p "$TEMP_PACKAGES_DIR"
  pushd "$TEMP_PACKAGES_DIR"
  for repo in $@; do
    git clone "$MIRROR_GITHUB_URL_PREFIX/$repo"
    repo_name=$(echo "$repo" | sed -E 's/.+\/(.+)\.git/\1/')
    pushd "$repo_name" && make clean install > /dev/null 2>&1 && popd
  done
  popd
}

# set mirror source
sed -i -E "s/#(Server = https?:\/\/mirrors\.aliyun\.com.*)/\1/" /etc/pacman.d/mirrorlist

pacman-key --init
pacman-key --populate
pacman --noconfirm --needed -Sy archlinux-keyring
pacman --noconfirm --needed -Syyu
pacman_install base base-devel vi reflector

pacman_install zsh git
# create user
useradd -m -g wheel -s /bin/zsh "$name"
echo "$name:$password" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/temp
chsh -s /bin/zsh "$name"

pacman_install openssh && systemctl enable sshd
pacman_install cronie && systemctl enable cronie

# install packages in packages.csv file
curl -fsL $MIRROR_GITHUB_URL_PREFIX/https://raw.github.com/neverwaiting/archinstall/master/packages.csv > /tmp/packages.csv
while IFS=',' read -a packs; do
  if [ "${packs[2]}" == "Y" ]; then
    if [ -z "${packs[0]}" ]; then
      if pacman -Ss "${packs[1]}" >> /dev/null; then
        pacpackages="$pacpackages ${packs[1]}"
      fi
    elif [ "${packs[0]}" == "Y" ]; then
      yaypackages="$yaypackages ${packs[1]}"
    elif [ "${packs[0]}" == "A" ]; then
      aurpackages="$aurpackages ${packs[1]}"
    elif [ "${packs[0]}" == "G" ]; then
      gitpackages="$gitpackages ${packs[1]}"
    fi
  fi
done < /tmp/packages.csv

[ -z "$pacpackages" ] || pacman_install "$pacpackages"
aur_install yay
[ -z "$aurpackages" ] || aur_install "$aurpackages"
[ -z "$yaypackages" ] || yay_install "$yaypackages"
[ -z "$gitpackages" ] || git_install "$gitpackages"

# set dotfiles
sudo -u "$name" git clone "$MIRROR_GITHUB_URL/neverwaiting/dotfiles.git" "$USER_HOME/dotfiles"&& \
sudo -u "$name" cp -r "$USER_HOME/dotfiles/.config" "$USER_HOME/" && \
sudo -u "$name" cp -r "$USER_HOME/dotfiles/.local" "$USER_HOME/" && \
sudo -u "$name" cp "$USER_HOME/dotfiles/.zprofile" "$USER_HOME/" && \
sudo -u "$name" cp "$USER_CONFIG_HOME/npm/npmrc" "$USER_HOME/.npmrc" || echo -e "########## set dotfiles error! ##########\n"

sudo -u "$name" nvm install 18

