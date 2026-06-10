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
