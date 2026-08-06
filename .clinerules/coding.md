---
paths:
  - "app/**"
  - "pyproject.toml"
  - "Dockerfile"
---

# remote-monitor Coding Standards

Hardware edge application for Raspberry Pi (Balena Cloud deployment): samples
ADC inputs over I2C (AB Electronics ADCPi), detects device state changes with
configurable normal/tamper values and debounce, publishes events to RabbitMQ,
and drives relay outputs (AB Electronics IOPi) from RabbitMQ trigger events.

## 1. Posture

- This project **extends the base-app architecture patterns** but uses a
  custom Debian-based image for Balena/hardware reasons. It keeps the same
  framework conventions: `tailucas_pylib` threading, ZMQ inproc transport,
  Sentry, 1Password credentials.
- Hardware is fallible: every I2C interaction needs timeout handling and
  degraded-mode behavior, never unbounded retries that block the sampling
  loop.

## 2. Application Architecture (`app/__main__.py`)

- Single-file application (by design for edge simplicity) with:
  - `Relay` — wraps one IOPi pin; `trigger(duration)` sets the pin high,
    sleeps, and always resets low in `finally` (fail-safe de-energize).
  - `RelayControl(AppThread)` — consumes relay trigger payloads from
    `URL_WORKER_RELAY_CTRL` (ZMQ PULL via pylib `ZMQListener`) and maps
    `device_key` → configured relay.
  - `main()` — ADC/IOPi board bring-up from `app.conf` (`adc_address`,
    `io_address`, `relay_address` sections), device mapping construction,
    sampling loop, heartbeat/notify publication to RabbitMQ.
- Sampling loop rules:
  - Sample interval is `SAMPLE_INTERVAL_SECONDS`; ADC timeouts wait 1s and
    continue.
  - Normal-value comparison uses `SAMPLE_DEVIATION_TOLERANCE`; tamper values
    override event detail when within tolerance.
  - Debounce with `device_history` keyed by `device_key` storing
    `(normalized_value, sampled_at, event_detail)`.
  - Publish `event.notify.*` when triggered devices exist, otherwise
    `event.heartbeat.*` after `HEARTBEAT_INTERVAL_SECONDS` of inactivity;
    payloads are built with `tailucas_pylib.data.make_payload`.

## 3. Configuration & Credentials

- Device topology comes entirely from `app.conf` sections: `input_type`,
  `input_name`, `input_location`, `input_address`, `input_normal_values`,
  `input_tamper_values`, `output_type`, `output_location`, `output_relay`,
  `adc_address`, `io_address`, `relay_address`, `rabbitmq`, `creds`.
- Secrets via pylib `Creds` (Sentry DSN etc.); hardware addresses are config,
  not secrets.

## 4. Dependencies

- Hardware libraries come from the ABElectronics Python libraries (ADCPi,
  IOPi) plus `pyserial`-style deps pinned in `pyproject.toml`; `pika` for
  RabbitMQ; `tailucas-pylib[monitoring,mq]`.
- Keep the app importable/testable on non-Pi hosts where possible (hardware
  calls only at runtime, not import time).

## 5. Deployment

- Balena Cloud target (see `.balena/`); Dockerfile is Debian-based with the
  same env contract as base-app (`APP_NAME`, `DEVICE_NAME`, `LOG_LEVEL`).
- Graceful shutdown: `die()` → stop listeners → close RabbitMQ → `zmq_term()`
  → `bye()`; relay pins must be de-energized by `Relay.trigger` finally-blocks.

## 6. Lint & Type Checks

- `make lint` runs ruff + mypy; both must pass (this project is stricter than
  most: keep ruff clean, mypy clean).
