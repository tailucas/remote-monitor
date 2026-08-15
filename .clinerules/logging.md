---
paths:
  - "app/**"
  - "src/**"
  - "internal/**"
  - "rapp/**"
  - "rlib/**"
  - "pom.xml"
---

# Structured Logging Standard (base-app)

All runtimes in this project log in **structured** style: a static event
message plus key/value fields. Interpolation (f-strings, `%`/`{}`
placeholders, concatenation) should be avoided and used only for descriptive
scalars with no query value of their own (e.g. a count embedded for
readability). Never interpolate secrets or untrusted data into a message.

## Python (`app/`)

The logger comes from the shared library:

```python
from tailucas_pylib import log

log.info("Sink socket started", extra={"zmq_url": self._zmq_url})
log.info(
    "Startup complete",
    extra={"env_var_count": len(env_vars), "env_vars": env_vars},
)
```

Rules:

1. Static message describing the event; all data in `extra` as a dict with
   `snake_case` keys.
2. Prefer a static message with data in `extra`. Interpolation is acceptable
   only for a descriptive scalar (e.g. a count or an identifier already
   present elsewhere in the record). Never interpolate secrets.
3. Exceptions: `log.exception("Static message", extra={...})` or
   `exc_info=True`.
4. Never log secrets (use masked hints or `*_set` booleans).
5. Output is JSON (python-json-logger) via pylib: stdout below ERROR, stderr
   from ERROR up; `SYSLOG_ADDRESS` routes INFO+ to syslog when configured.

## Java (`src/`)

Use the SLF4J 2.x **fluent logging API** backed by Log4j2 with
`JsonTemplateLayout` (Logstash JSON event layout), configured in
`src/main/resources/log4j2.xml`:

```java
log.atInfo().setMessage("App Device Name")
    .addKeyValue("device_name", appConfig.get("app", "device_name"))
    .log();

log.atError().setMessage("Cannot read application configuration").setCause(e).log();
```

Rules:

1. Always `log.at<Level>().setMessage(...).addKeyValue(...).log()`; chain one
   `addKeyValue` per field. Exceptions use `.setCause(e)`.
2. Prefer a static message with fields via `addKeyValue`. Interpolation is
   acceptable only for a descriptive scalar (e.g. a count or an identifier
   already present elsewhere in the record). Never interpolate secrets.
3. Conditional logging uses the builder's level check, e.g.
   `log.atDebug().setMessage(...).log()` only when enabled; prefer
   `log.isEnabledForLevel(Level.DEBUG)` guards for expensive field assembly.
4. `log4j2.xml` uses `JsonTemplateLayout` with
   `classpath:LogstashJsonEventLayoutV1.json` on the Console appender; root
   level comes from `${env:LOG_LEVEL:-INFO}`. An `<OpenTelemetry/>` appender
   bridges log records into OTLP for log↔trace correlation — see
   `observability.md` for the required `OpenTelemetryAppender.install(sdk)`
   step. The Syslog appender snippet is opt-in (uncomment + define
   `SYSLOG_HOST`).
5. Dependencies: `log4j-core`, `log4j-slf4j2-impl`,
   `log4j-layout-template-json` (pinned via `log4j.version` in `pom.xml`) with
   `slf4j-api`. Do not reintroduce `slf4j-simple`.

## Go (`internal/`)

Use the standard library `log/slog` with structured attributes:

```go
slog.Info("hello", "component", "main")
```

Avoid `fmt.Println` for anything operational. (The current
`internal/main.go` is a hello-world stub using `fmt.Println`; convert it to
`log/slog` before adding operational logging.)

## Rust (`rapp/`, `rlib/`)

For operational logging, use a structured facade (`tracing` or `log` with a
JSON emitter) rather than `println!`. Demo output may use `println!` only
where no logging semantics are intended.

## Syslog

- **Python:** set `SYSLOG_ADDRESS` (e.g. `host:514`) to route INFO+ to the
  container host's rsyslog via pylib's `SysLogHandler`.
- **Java:** the Log4j2 `Syslog` appender takes `host` and `port` separately
  (no full-URL appender exists), so it uses `SYSLOG_HOST` — see the
  commented appender in `src/main/resources/log4j2.xml`.

## Levels

Choose the level by the *consequence* of the event, not by how interesting it
is. Default to the lowest level that still tells the story, and follow
**one event = one line**: a single logical event produces a single structured
record with all context in its fields.

| Level | Use |
|---|---|
| DEBUG | The default for routine, per-message/per-iteration detail: internal state, field values, step-by-step progress. Safe to drop in production. |
| INFO | An action of consequence to an upstream or downstream dependency — e.g. taking an action, triggering a mutation, a state transition, or a lifecycle boundary (startup/shutdown). Something an operator would want to see in normal operation. |
| WARNING | A non-error variation of normal logic, or a situation where the correct action is ambiguous: retries, fallbacks, degraded mode, unexpected-but-handled input. Execution continues. |
| ERROR | An exception or condition where normal execution cannot continue — e.g. returning after catching an exception, or abandoning a unit of work. |
| CRITICAL | The process is about to exit or is in an unrecoverable app-level state. Reserved for fatal failures. |

> `TRACE` (below DEBUG) exists in Log4j2 and some facades but not in Python
> stdlib or Go `log/slog`, so it is not portable across runtimes and should
> not be relied on for cross-language code.

### Exception handling

- **Log once, at the boundary.** Do not log-and-rethrow the same exception at
  every layer. Log where the error is handled (or where execution stops), and
  let the trace carry the rest of the context.
- **Non-recoverable errors must be captured in the trace.** For every ERROR
  where execution cannot continue, record the exception on the active span —
  `record_exception` in Python, `span.recordException(...)` in Java — and set
  the span status to ERROR, so the failure is queryable in the trace, not
  only in the log.
- **Recoverable problems are WARNING, not ERROR.** A retry that succeeds is
  a WARNING (or DEBUG if routine); escalate to ERROR only when the work is
  abandoned.
