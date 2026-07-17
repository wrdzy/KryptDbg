# KryptDbg

KryptDbg is a modular Roblox runtime debugging workspace. It uses one custom
`KryptUI` window, a shared runtime, and feature modules that are downloaded only
when their tab is opened for the first time.

Use it only in experiences you own or have explicit permission to test.

## Loader

Execute this one bootstrap:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/wrdzy/KryptDbg/main/init.lua"))()
```

`init.lua` downloads only the manifest, `KryptUI`, and the runtime at startup.
Explorer is then mounted as the default workspace. Remotes, Scripts, Console,
and Diagnostics are fetched on demand and stay mounted after loading, so their
state and subscriptions continue to coexist.

Set `getgenv().KryptDbgBaseUrl` before running the bootstrap to test a fork or a
different branch.

## Architecture

```text
init.lua
 ├─ src/Manifest.lua
 ├─ src/KryptUI.lua
 └─ src/Runtime.lua
     ├─ shared selection + highlight
     ├─ event bus + cleanup lifecycle
     └─ lazy feature loader
         ├─ Explorer.lua
         ├─ Remotes.lua
         ├─ Scripts.lua
         ├─ Console.lua
         └─ Diagnostics.lua
```

Feature modules depend on the runtime context instead of depending directly on
one another. The context supplies the shared UI library, services, selection,
events, clipboard, status, serialization, and cleanup APIs. This keeps module
boundaries clear while allowing loaded tools to work together.

## KryptUI

`src/KryptUI.lua` is the project-specific retained-mode UI library. It provides:

- One professional IDE-style window and tab rail
- Consistent colors, typography, spacing, panels, inputs, buttons, and lists
- A dedicated drag region and eight edge/corner resize zones
- Viewport clamping, minimum/maximum sizing, minimize, and RightShift visibility
- Status bar, module load indicators, toasts, empty states, and shared primitives
- Mouse and touch input support

The component approach was informed by
[React Luau](https://github.com/Roblox/react-luau), the lightweight debugging
workflow of [Iris](https://github.com/Michael-48/Iris), and the tab/group
organization of [LinoriaLib](https://github.com/violin-suzutsuki/LinoriaLib).
KryptUI is custom code and does not embed those libraries.

## Features

### Explorer

- Searchable, expandable DataModel hierarchy
- Optional nil-instance roots when supported
- Shared selection and viewport highlighting
- Armed world-object picker
- Curated properties and attributes editor
- Copyable instance paths and bounded asynchronous search

### Remotes

- Capability-gated `FireServer` and `InvokeServer` capture
- Search, method filters, pause, deduplication, and bounded history
- Generated Luau with depth/cycle limits
- Controlled replay of the selected captured call
- Exact-instance block and exclude controls

### Scripts

- Asynchronous bounded script indexing
- Shared selection with Explorer
- Capability-gated decompile or readable `Source` fallback
- Clipboard and filesystem export when supported

### Console

- Output, information, warning, and error capture
- Search and level filters with bounded history
- Capability-gated command bar and command history

### Diagnostics

- FPS, frame-time, memory, and network metrics
- Runtime capability matrix
- Lazy-module status
- Copyable report and capability-gated Save Instance

## Shortcuts

- `Ctrl+1` through `Ctrl+5` switch workspaces
- `RightShift` hides or restores the window

## Development

```powershell
pnpm install
pnpm test
```

The validation script parses every Lua file and checks that every manifest
dependency exists.

## Limitations

- Features relying on executor-specific APIs remain disabled when unavailable.
- Large hierarchies, script indexes, logs, and searches are capped to protect
  frame rate and memory.
- The suite requires HTTP and `loadstring` support for remote module loading.
- No stealth, anti-detection, or detection-evasion behavior is included.
