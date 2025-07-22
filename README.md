# OpenWrt WireGuard Ineractive Installer

An interactive shell script to quickly and safely configure a WireGuard VPN server on an OpenWrt router.

It guides you through generating keys, applying network and firewall settings, and creating ready-to-import `.conf` files for client devices — with optional QR code output for mobile use and built-in rollback for peace of mind.

---

## ✨ Features

- ✅ Interactive prompts for all setup variables
- ✅ Generates secure keypairs and `.conf` files for each peer
- ✅ Optional QR code output for mobile devices
- ✅ Automatically applies UCI network and firewall rules
- ✅ Creates timestamped backups and supports rollback
- ✅ Built specifically for OpenWrt (no external scripts or hacks)

---

## 🧱 Requirements

- OpenWrt 23.05 or newer
- Installed packages:
  ```sh
  opkg update
  opkg install wireguard-tools luci-app-wireguard
  ```
- (Optional for QR codes):
  ```sh
  opkg install qrencode
  ```

---

## 📥 Installation

1. **Download the script**:
   ```sh
   curl -O https://raw.githubusercontent.com/Coralesoft/openwrt-wireguard-installer/main/interactive-wg-setup.sh
   chmod +x interactive-wg-setup.sh
   ```

2. **Run it as root** on your OpenWrt router:
   ```sh
   ./interactive-wg-setup.sh
   ```

---

## ⚙️ Usage

The script will prompt you to:
- Name the WireGuard interface
- Set port, address, zones, and DNS
- Enter your public endpoint (`host:port`)
- Define the number of peers
- Provide each peer’s name and IP

Each peer will get:
- A secure private key
- A complete `.conf` file (for use in desktop or mobile clients)
- An optional QR code displayed in the terminal (if `qrencode` is installed)

---

## 📂 Output

All generated files are saved under:

```
/etc/wireguard/
  ├── privatekey            # Server key
  ├── publickey             # Server key
  └── peers/
        ├── phone.conf
        ├── phone-privatekey
        ├── phone-publickey
        └── ...
```

---

## 🔄 Rollback

At the end of the setup, you’ll be prompted to roll back your changes.  
If confirmed, it restores:

- `/etc/config/network.bak.<timestamp>`
- `/etc/config/firewall.bak.<timestamp>`

---

## 🧪 Example

A sample generated `.conf` for a peer:

```ini
[Interface]
PrivateKey = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Address = 192.168.20.2/32
DNS = 192.168.20.1

[Peer]
PublicKey = yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

Import this into the **WireGuard app** on iOS/Android, or use with `wg-quick` on desktop.

---

## 📌 Roadmap

- [ ] Add uninstall/teardown script - in progress 
- [ ] Regenerate or revoke peer keys
- [ ] Add script to regenerate peer QR codes


---

## 🛡 License

MIT License © 2025 C. Brown  
Feel free to use, modify, and share.

---

## 💬 Feedback

Pull requests, issues, and suggestions are welcome.  
Open an issue at [github.com/Coralesoft/openwrt-wireguard-installer/issues](https://github.com/Coralesoft/openwrt-wireguard-installer/issues).
---

## 🧹 Uninstall

To remove all WireGuard configuration, keys, peers, and firewall rules, use the included uninstall script.

### Usage

Run normally to uninstall:

```sh
./wg-uninstall.sh
```

Run in dry-run mode to preview what will be removed:

```sh
./wg-uninstall.sh --dry-run
```
