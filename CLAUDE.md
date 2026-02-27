# vphone-cli

Virtual iPhone boot tool using Apple's Virtualization.framework with PCC research VMs.

See [AGENTS.md](./AGENTS.md) for project conventions, architecture, and design system.

## Quick Reference

- **Build:** `./build_and_sign.sh`
- **Boot (headless):** `./boot.sh`
- **Boot (DFU):** `./boot_dfu.sh`
- **Python venv:** `zsh Scripts/create_venv.sh` (installs to `.venv/`, activate with `source .venv/bin/activate`)
- **Platform:** macOS 14+ (Sequoia), SIP/AMFI disabled
- **Language:** Swift 5.10 (SwiftPM), ObjC bridge for private APIs
- **Python deps:** `capstone`, `keystone-engine`, `pyimg4` (see `requirements.txt`)
