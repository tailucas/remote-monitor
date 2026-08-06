---
paths:
  - "app/**"
---

# Structured Logging Standard (remote-monitor)

All logging is **structured**: a static event message plus an `extra` dict of
`snake_case` fields. Interpolated log messages (f-strings, `%`-args,
`.format()`, concatenation) are prohibited.

## The Logger

```python
from tailucas_pylib import log
```

JSON output (python-json-logger) configured by `tailucas_pylib`: stdout below
ERROR, stderr from ERROR up; `SYSLOG_ADDRESS` routes INFO+ to syslog when set.
Every `extra` key becomes a top-level JSON field.

## The Pattern

```python
log.info(
    "Activating relay",
    extra={"relay_name": self._name, "duration_secs": duration},
)
log.warning(
    "Timeout reading value from ADC",
    exc_info=True,
    extra={"adc_name": adc_name, "pin": pin},
)
log.info(
    "Device event triggered",
    extra={
        "device_event_distinction": device_event_distinction,
        "event_detail": event_detail,
        "sampled_value": normalized_value,
    },
)
```

Never:

```python
log.info(f"Activating {self._name} for {duration} seconds.")
log.info(message.format("RabbitMQ control"))
log.warning(f"When closing: {e!s}")
```

## Rules

1. **Static message; data in `extra`** with `snake_case` keys and
   JSON-friendly values.
2. **Hardware mappings are logged at startup** as discrete events
   ("Configuring ADC", "Mapped relay to IO", "ADC pin will detect device")
   so the device topology is reconstructable from logs alone.
3. **Exceptions:** `exc_info=True` for timeouts/failures where the traceback
   matters; otherwise `"error": str(e)` in `extra`.
4. **Sampled logging:** the ADC comparison loop is hot — keep per-sample
   comparison logs behind the `randint(0, 1000)` sampling guard already used
   in the code, and keep debounce logs similarly sampled.
5. **Shutdown sequence** logs use explicit static messages per component
   ("Shutting down RabbitMQ control listener...", "Shutting down RabbitMQ
   worker...") — no templated message variables.
6. **Levels.** DEBUG for sample comparisons/debounce; INFO for mapping,
   startup, relay events, device triggers; WARNING for ADC timeouts,
   malformed payloads, close errors; ERROR for unmapped device keys and
   malformed control payloads.
