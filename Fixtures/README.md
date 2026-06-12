# CLI output fixtures

Real output captured from Apple `container` CLI **1.0.0** on 2026-06-10 (macOS 26.5.1),
using a scratch container (`container run -d --name plan-test alpine:latest sleep 600`).
Used by decoder unit tests; re-capture if the CLI version changes.

| File | Command | Notes |
|---|---|---|
| `list-all.json` | `container list --all --format json` | one running container |
| `list-all-stopped.json` | `container list --all --format json` | same container, stopped |
| `stats.json` | `container stats --format json --no-stream` | running container |
| `list-all-ports.json` | `container list --all --format json` | container run with `-p 8080:80` (captured 2026-06-10) |
| `inspect.json` | `container inspect plan-test` | array of full container objects |

## Observed shapes (the facts the DTOs are built on)

`list`/`inspect` element — three top-level keys: `id` (string), `configuration` (object),
`status` (object — NOT a string):

- `configuration.creationDate` — ISO 8601 (`2026-06-10T14:29:21Z`)
- `configuration.image.reference` — e.g. `docker.io/library/alpine:latest`
- `configuration.initProcess.executable` + `.arguments` — command
- `configuration.publishedPorts` — array; populated element shape (see `list-all-ports.json`):
  `{containerPort: Int, count: Int, hostAddress: String, hostPort: Int, proto: String}`
- `configuration.resources.cpus` / `.memoryInBytes`
- `status.state` — `"running"` / `"stopped"` (observed values)
- `status.startedDate` — ISO 8601; **retained after stop**
- `status.networks[].ipv4Address` — e.g. `192.168.64.2/24`

`stats` element (flat): `id`, `cpuUsageUsec` (cumulative — NO percentage field),
`memoryUsageBytes`, `memoryLimitBytes`, `networkRxBytes`, `networkTxBytes`,
`blockReadBytes`, `blockWriteBytes`, `numProcesses`. Only running containers appear.

Other verified behaviors:

- When the apiserver is stopped, every command exits non-zero with stderr containing
  `XPC connection error` and the hint `container system start`.
- `container system status` exits 0 with a key/value table when running; exits 1 with
  `apiserver is not running and not registered with launchd` when stopped.
- First run requires a kernel: `container system start` prompts to install one
  (non-interactive runs fail with "failed to read user input");
  `container system kernel set --recommended` installs it non-interactively.

## Image fixtures (captured 2026-06-11, CLI 1.0.0)

| File | Command | Notes |
|---|---|---|
| `image-list.json` | `container image list --format json` | two images: alpine:latest, postgres:latest |
| `image-inspect.json` | `container image inspect alpine:latest` | array (single element); same shape as list element |

`image-list.json` element shape (top-level keys: `id`, `configuration`, `variants`):

- `id` — sha256 hex digest of the index manifest (no `sha256:` prefix)
- `configuration.name` — fully-qualified ref, e.g. `docker.io/library/alpine:latest`
- `configuration.creationDate` — ISO 8601 (`2026-06-09T20:11:09Z`)
- `configuration.descriptor` — manifest descriptor object:
  - `descriptor.size` — **manifest index size in bytes (~9 KB), NOT the image data size**.
    Do not use this for storage reporting; the real on-disk weight is the sum of
    `variants[].size`.
  - `descriptor.digest` — sha256 digest of the manifest
  - `descriptor.mediaType` — OCI media type string
- `variants[]` — one entry per platform variant pulled locally:
  - `variants[].size` — uncompressed layer sum for that variant (bytes); real image weight
  - `variants[].platform.architecture` — e.g. `"arm64"`, `"amd64"`, `"arm"`, `"unknown"`
  - `variants[].platform.os` — e.g. `"linux"`, `"unknown"`
  - `variants[].platform.variant` — e.g. `"v8"`, `"v7"` (may be absent)
  - `variants[].digest` — sha256 digest of the platform-specific manifest
  - `variants[].config` — full OCI image config (skip — not decoded by the app)

`image inspect` (no `--format` flag — the CLI does not support one): returns a
pretty-printed JSON array with the **same element shape** as `image list --format json`.
It takes name refs (`alpine:latest`), not digest IDs.

Observed sizes for the alpine:latest fixture (1 variant):
- `configuration.descriptor.size` = 9218 (manifest, ~9 KB — do NOT display this)
- `variants[0].size` = 4203982 (arm64 layer data, ~4 MB — the real image size)

## Compose fixtures (container-compose 0.12.0, captured/authored 2026-06-12)

| File | Type | Notes |
|---|---|---|
| `compose-named.yml` | Authored | Top-level `name: myapp`, three services (`web`, `db`, `cache`) in non-alphabetical declaration order, `image:` refs, `depends_on` on `web` (array form) |
| `compose-unnamed.yml` | Authored | No `name:`, one service with `${TAG:-latest}` image ref (kept raw), one null-body service (`cache:`) |

These are authored (not captured) fixture files used by `ComposeFileParserTests`.

### Live-verified facts (container-compose 0.12.0 + container runtime 1.0.0, 2026-06-12)

- `container-compose --version` prints: `container-compose version 0.12.0`
- With the apiserver stopped, `container-compose up` exits 1 with stderr:
  `Error: XPC connection error: Connection invalid`
  (the `container system start` hint does **not** appear — unlike the `container` CLI)
- Info/progress lines go to **stdout** with `\r` rewrites; final lines include
  `<service>: <container-id>`.
- **Naming (live-verified)**:
  - `name: probeproj` in compose file → container `probeproj-web`
  - Folder `my.app` without `name:` → `my_app-web` (dots replaced with underscores)
- ⚠ **`container-compose down` 0.12.0 is broken against container runtime 1.0.0**:
  XPC protocol mismatch (`DecodingError.typeMismatch … Path: signal`); container keeps
  running. `down` is implemented via `ContainerRuntime.stop(id:)` per matched container
  in reverse YAML service order instead. Revisit when the brew formula reaches 1.0.0+.
