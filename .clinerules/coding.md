---
paths:
  - "app/**"
  - "src/**"
  - "internal/**"
  - "rapp/**"
  - "rlib/**"
  - "pom.xml"
  - "pyproject.toml"
  - "*.sh"
  - "Dockerfile"
---

# base-app Coding Standards

base-app is the **reference implementation** and template for all derived
applications. It is intentionally batteries-included boilerplate: an
Ubuntu-based Docker app with a Python core and optional Java, Go, and Rust
components orchestrated by supervisord.

## 1. Posture

- **Template-first.** Changes here set the standard for every derived app.
  Prefer generic, well-documented patterns over feature-specific code.
  event-processor is the most advanced derivative; when it proves a better
  pattern (e.g. structured logging), backport it here.
- **Boring and explicit.** Boilerplate is a feature: entrypoints, setup
  scripts, and configuration stay readable and copy-paste-able.

## 2. Python Application (`app/`)

- The app follows the `tailucas_pylib` framework: `AppThread` subclasses,
  ZMQ inproc transport (`URL_WORKER_*`), `exception_handler` for socket
  lifecycles, `SignalHandler` + `thread_nanny` + `die()`/`bye()` shutdown.
- Startup order in `main()`: creds validation → Sentry init → signal handler
  → worker threads → thread nanny → `log.setLevel(logging.INFO)` →
  `interruptable_sleep.wait()` → `die()`/`zmq_term()`/`bye()` in cleanup.
- Dependencies are managed with `uv` (`pyproject.toml`, `uv.lock`); depend on
  `tailucas-pylib[...]` extras, never vendored copies.
- Lint with ruff/mypy per the project config before considering work done.

## 3. Java Application (`src/`, `pom.xml`)

- Plain Maven jar (no framework); the entry point is `tailucas.app.App`,
  packaged as `app.jar` (jar-with-dependencies) and run by supervisord.
- Logging: SLF4J 2.x **fluent API** with Log4j2 JSON output — see
  `logging.md`. Never use `System.out.println` for operational messages.
- Keep dependencies minimal; pin versions as `pom.xml` properties.

## 4. Go (`internal/`) and Rust (`rapp/`, `rlib/`)

- Go and Rust components are optional demo runtimes (`RUN_GO_APP`,
  `RUN_RUST_APP` env switches in `.env`).
- New Go code should use `log/slog` with structured attributes
  (`slog.Info("event", "key", value)`); avoid `fmt.Printf`-style logging
  for operational output.
- New Rust code SHOULD use a structured logging facade (`tracing` or `log`)
  instead of `println!` for operational output.

## 5. Configuration & Environment

Configuration, secrets, and the `.env` → `config_interpol` flow are documented
in `config.md`. The container lifecycle, entrypoint layering, and supervised
program generation are documented in `container.md`.

## 6. Build & Run

The Makefile build graph and the Python/Java/Rust/Go toolchain conventions are
documented in `build.md`. The Docker multi-stage build and run-as-user
conventions are documented in `container.md`.

## 7. Cross-cutting Rules

- Every language runtime logs in structured style (see `logging.md`).
- Graceful shutdown is mandatory in every runtime (signal handling, resource
  teardown).
- New integrations get a feature switch (env var or `app.conf` section) so
  the template stays runnable with zero external dependencies.
