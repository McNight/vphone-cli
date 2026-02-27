# AGENTS — vphone-cli

## Project Overview

CLI tool that boots virtual iPhones (PV=3) via Apple's Virtualization.framework, targeting Private Cloud Compute (PCC) research VMs. Used for iOS security research — firmware patching, boot chain modification, and runtime instrumentation.

## Architecture

```
Sources/
├── VPhoneObjC/           # ObjC bridge for private Virtualization.framework APIs
│   ├── include/VPhoneObjC.h
│   └── VPhoneObjC.m
└── vphone-cli/           # Swift executable
    ├── VPhoneCLI.swift          # Entry point, ArgumentParser command
    ├── VPhoneVM.swift           # VM configuration and lifecycle
    ├── VPhoneHardwareModel.swift # PV=3 hardware model creation
    └── VPhoneVMWindow.swift     # AppKit window + touch input translation

Scripts/
├── patch_firmware.py     # Patches 6 boot-chain components (41+ modifications)
├── build_ramdisk.py      # Builds SSH ramdisk for device setup
├── install_cfw.sh        # Installs custom firmware to VM disk
├── patch_cfw.py          # Patches individual CFW components
├── prepare_firmware.sh   # Extracts and prepares IPSW firmware
└── ramdisk_send.sh       # Sends ramdisk to device via irecovery
```

### Key Patterns

- **Private API access:** All private Virtualization.framework calls go through the ObjC bridge (`VPhoneObjC`). Swift code never calls private APIs directly.
- **Function naming:** ObjC bridge functions use the `VPhone` prefix (e.g., `VPhoneCreateHardwareModel`, `VPhoneConfigureSEP`).
- **Configuration:** CLI options parsed via `ArgumentParser`, converted to `VPhoneVM.Options` struct, then used to build `VZVirtualMachineConfiguration`.
- **Error handling:** `VPhoneError` enum with `CustomStringConvertible` for user-facing messages.
- **Window management:** `VPhoneWindowController` wraps `NSWindow` + `VZVirtualMachineView`. Touch input translated from mouse events to multi-touch via `VPhoneVMView`.

## Coding Conventions

### Swift

- **Style:** Pragmatic, minimal. No unnecessary abstractions.
- **Sections:** Use `// MARK: -` to organize code within files.
- **Access control:** Default (internal). Only mark `private` when needed for clarity.
- **Async:** Use `async/await` for VM lifecycle. `@MainActor` for UI and VM start operations.
- **Naming:** Types are `VPhone`-prefixed (`VPhoneVM`, `VPhoneWindowController`). Match Apple framework conventions.

### ObjC Bridge

- All functions are C-style (no ObjC classes exposed to Swift).
- Return `nil`/`NULL` on failure — caller handles gracefully.
- Header documents the private API being wrapped in each function's doc comment.

### Shell Scripts

- Use `zsh` with `set -euo pipefail`.
- Scripts are self-contained — they `cd` to their own directory.
- Build script (`build_and_sign.sh`) handles both compilation and entitlement signing.

### Python Scripts

- Firmware patching scripts use `capstone` (disassembly), `keystone-engine` (assembly), and `pyimg4` (IM4P handling).
- Each patch is logged with offset and before/after state.
- Scripts operate on a VM directory and expect specific file layout.
- **Environment:** Use the project venv (`source .venv/bin/activate`). Create with `zsh Scripts/create_venv.sh`. All deps listed in `requirements.txt`.

## Build & Sign

The binary requires private entitlements to use PV=3 virtualization:

- `com.apple.private.virtualization`
- `com.apple.private.virtualization.security-research`
- `com.apple.security.virtualization`
- `com.apple.vm.networking`
- `com.apple.security.get-task-allow`

Always use `build_and_sign.sh` — never `swift build` alone, as the unsigned binary will fail at runtime.

## Design System

### Intent

**Who:** Security researchers working with Apple firmware and virtual devices. Technical, patient, comfortable in terminals. Likely running alongside GDB, serial consoles, and SSH sessions.

**Task:** Boot, configure, and interact with virtual iPhones for firmware research. Monitor boot state, capture serial output, debug at the firmware level.

**Feel:** Like a research instrument. Precise, informative, honest about internal state. No decoration — every pixel earns its place.

### Palette

- **Background:** Dark neutral (`#1a1a1a` — near-black, low blue to reduce eye strain during long sessions)
- **Surface:** `#242424` (elevated panels), `#2e2e2e` (interactive elements)
- **Text primary:** `#e0e0e0` (high contrast without being pure white)
- **Text secondary:** `#888888` (labels, metadata)
- **Accent — status green:** `#4ade80` (VM running, boot success)
- **Accent — amber:** `#fbbf24` (DFU mode, warnings, in-progress states)
- **Accent — red:** `#f87171` (errors, VM stopped with error)
- **Accent — blue:** `#60a5fa` (informational, links, interactive highlights)

Rationale: Dark surfaces match the terminal-adjacent workflow. Status colors borrow from oscilloscope/JTAG tooling — green for good, amber for attention, red for fault. No brand colors — this is a tool, not a product.

### Typography

- **UI font:** System monospace (SF Mono / Menlo). Everything in this tool is technical — monospace respects the content.
- **Headings:** System sans (SF Pro) semibold, used sparingly for section labels only.
- **Serial/log output:** Monospace, `#e0e0e0` on dark background. No syntax highlighting — raw output, exactly as received.

### Depth

- **Approach:** Flat with subtle 1px borders (`#333333`). No shadows, no blur. Depth through color difference only.
- **Rationale:** Shadows suggest consumer software. Borders suggest instrument panels. This is an instrument.

### Spacing

- **Base unit:** 8px
- **Component padding:** 12px (1.5 units)
- **Section gaps:** 16px (2 units)
- **Window margins:** 16px

### Components

- **Status indicator:** Small circle (8px) with color fill + label. No animation — state changes are instantaneous.
- **VM display:** Full-bleed within its container. No rounded corners on the display itself.
- **Log output:** Scrolling monospace region, bottom-anchored (newest at bottom). No line numbers unless requested.
- **Toolbar (if present):** Icon-only, 32px touch targets, subtle hover state (`#2e2e2e` -> `#3a3a3a`).
