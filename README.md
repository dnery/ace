## Assumptions

- `ace` is aliased in local machine `hosts` file

## Initial Setup

Update keyring:
```bash
pacman -Sy archlinux-keyring
```

If any issues are found, attempt keyring refresh:
```bash
pacman-key --refresh-keys
pacman -Syu
```
    
Or alternatively, if all else fails, do a full keyring reset:
```bash
rm -r /etc/pacman.d/gnupg
pacman-key --init
pacman-key --populate archlinux
pacman-key --refresh-keys
pacman -Sc (clean cache)
pacman -Syyu
```

Rank mirrors, then update system:
```bash
pacman -S python reflector neovim

reflector \
    --country Brazil \
    --protocol https \
    --age 24 \
    --sort rate \
    --latest 10 \
    --save /etc/pacman.d/mirrorlist

pacman -Syu

# IMPORTANT
mkinitcpio -P

# IMPORTANT
grub-mkconfig -o /boot/grub/grub.cfg
```

**Now reboot the machine.**

## Baseline Hardening

```bash
# Create user with sudo
pacman -S --noconfirm fish
useradd -m -G wheel -s /bin/fish danilo
passwd danilo

# Copy over sshd conrfig
mkdir -p /home/danilo/.ssh
cp .ssh/authorized_keys /home/danilo/.ssh/authorized_keys
chown -R danilo:danilo /home/danilo/.ssh
```

Create `/etc/sudoers.d/danilo` with:
```conf
## Suggestions pulled from default sudoers

# This preserves proxy settings from user environments of root
# equivalent users (group sudo)
Defaults:%sudo env_keep += "http_proxy https_proxy ftp_proxy all_proxy no_proxy"

# This allows running arbitrary commands, but so does ALL, and it means
# different sudoers have their choice of editor respected.
Defaults:%sudo env_keep += "EDITOR"

# Completely harmless preservation of a user preference.
Defaults:%sudo env_keep += "GREP_COLOR"

# While you shouldn't normally run git as root, you need to with etckeeper
Defaults:%sudo env_keep += "GIT_AUTHOR_* GIT_COMMITTER_*"

# Per-user preferences; root won't have sensible values for them.
Defaults:%sudo env_keep += "EMAIL DEBEMAIL DEBFULLNAME"

# "sudo scp" or "sudo rsync" should be able to use your SSH agent.
Defaults:%sudo env_keep += "SSH_AGENT_PID SSH_AUTH_SOCK"

# Ditto for GPG agent
Defaults:%sudo env_keep += "GPG_AGENT_INFO"

## Custom configuration for my linuxbox user

# Preserve my zsh config for christ's sakes
# Defaults:%sudo env_keep += "ZDOTDIR"

# Preserve my XDG user base just in case
# TODO

# Allow sudo no-password permissions
danilo ALL=(ALL) NOPASSWD:ALL
```

**End session, restart as non-root user.**

Now finalize hardening:
```bash
# SSH hardening
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sudo sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Time & logs
sudo timedatectl set-timezone America/Sao_Paulo
sudo sed -i 's/^#\?Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
sudo systemctl restart systemd-journald
```

## UFW + Fail2ban

Set up UFW:
```bash
sudo pacman -S --noconfirm ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

Install Fail2ban:
```bash
sudo pacman -S --noconfirm fail2ban
```

Create `/etc/fail2ban/jail.local` with:
```conf
[DEFAULT]
bantime = 1h
findtime = 15m
maxretry = 5
backend = systemd
banaction = ufw

[sshd]
enabled = true
```

Start `fail2ban` and check `sshd` status via client:
```bash
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd
```

## Lock SSH to Tailscale

Have Tailscale running on your current machine, then in the VPS:
```fish
sudo pacman -S --noconfirm tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up --ssh
```

Once setup is complete, **Tailscale will likely update your machine's hosts file and you'll be booted.**

**Remove the outdated alias for `ace` from your hosts file, and SSH back into the VPS.**

Now update UFW:
```fish
sudo ufw deny ssh && sudo ufw allow in on tailscale0 to any port 22 proto tcp
```

## Prepare for rootless Docker

Verify that `/etc/subuid` and `/etc/subgid` contain at least 65,536 subordinate UIDs/GIDs for the user.
Here I have 65,536 subordinate UIDs/GIDs (231072-296607):
```fish
$ id -u
1001

$ whoami
testuser

$ grep ^$(whoami): /etc/subuid
testuser:231072:65536

$ grep ^$(whoami): /etc/subgid
testuser:231072:65536
```

Verify that `99-docker-rootless` conf is being added somewhere in the [docker-rootless-extras PKGBUILD.](https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h=docker-rootless-extras)
If it's not, manually create the /etc/sysctl.d/99-rootless-docker.conf` file with:
```conf
kernel.unprivileged_userns_clone=1
```

And then run:
```fish
sudo sysctl --system
```

Now finally install Docker with optionals:
```fish
sudo pacman -S --noconfirm docker docker-buildx pigz fuse-overlayfs
```

## Install and start rootless Docker

```fish
# Install an AUR helper
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si

# Install rotless extras
yay -S docker-rootless-extras
```

Verify `subuid` and `subgid` files:
```fish
# /etc/subuid
danilo:165536:65536

# /etc/subgid
danilo:165536:65536
```

Enable the `docker.socket` user unit:
```fish
systemctl --user enable --now docker.socket
```

Set the docker socket env var:
```fish
# Verify
echo $XDG_RUNTIME_DIR
set -Ux DOCKER_HOST unix://$XDG_RUNTIME_DIR/docker.sock
```

Finally check that stuff runs **without `sudo`:**
```fish
docker run -it --rm archlinux bash -c "echo hellow world"
```
