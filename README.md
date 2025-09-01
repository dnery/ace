# General Purpose Arch VPS Configuration

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

Rank mirrors and update system:
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

mkinitcpio -P  # DON'T FORGET!!!

grub-mkconfig -o /boot/grub/grub.cfg  # DON'T FORGET!!!
```

**Now reboot the machine.**

## Baseline Hardening

```bash
# Create user with sudo
pacman -S --noconfirm fish
useradd -m -G wheel -s /bin/fish danilo
passwd danilo

# Copy over sshd config
mkdir -p /home/danilo/.ssh
cp .ssh/authorized_keys /home/danilo/.ssh/authorized_keys
chown -R danilo:danilo /home/danilo/.ssh
```

**Put/create the [sudoers file](danilo) in `/etc/sudoers.d/danilo`, end the session, and restart as non-root.**

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

Put/create the [Jailfile](jail.local) in `/etc/fail2ban/jail.local`.

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

## Prepare for Rootless Docker

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
If it's not, put/create the [rootless Docker config](99-my-rootless-docker.conf) in `/etc/sysctl.d/99-my-docker-rootless.conf`.

And then run:
```fish
sudo sysctl --system
```

Now finally install Docker with optionals:
```fish
sudo pacman -S --noconfirm docker docker-buildx pigz fuse-overlayfs
```

## Install and Start Rootless Docker

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

## Caddy (Global Reverse Proxy)


```fish
sudo pacman -S --noconfirm caddy
sudo systemctl enable --now caddy
```

Put/create the [global Caddyfile](Caddyfile) in `/etc/caddy/Caddyfile`.

Finalize the setup:
```fish
sudo mkdir -p /var/log/caddy
sudo chown -R caddy:caddy /var/log/caddy
sudo systemctl reload caddy
```

Initially, create **DNS-only** A-records in Cloudflare:
- `arena.dznery.com` -> A -> VPS IPv4
- `migrator.dznery.com` -> A -> VPS IPv4

**Reload Caddy if needed,** accessing the URLs should give you `502`s. (NOT `525`s.)

At this point the certificates are acquired and you can update the DNS config in Cloudflare:
- `arena` -> CNAME -> `dznery.com`
- `migrator` -> CNAME -> `dznery.com`

**SSL/TLS mode should be set to "Full (strict)" as well.**
