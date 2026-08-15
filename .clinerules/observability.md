# base-app Observability Rules (OpenTelemetry)

base-app demonstrates the reference OTEL pattern: logs, metrics, and
traces exported via OTLP. The exporter target comes from the standard
`OTEL_EXPORTER_OTLP_*` env vars (currently the Grafana Cloud OTLP gateway
via `OTEL_EXPORTER_OTLP_ENDPOINT`; a local `OTEL_COLLECTOR_URL` is also
available for self-hosted collectors). These rules are the standard for
derived applications. The implementations in `app/__main__.py` (Python)
and `src/main/java/tailucas/app/` (Java) are the canonical examples.

## 1. General Pattern (language-agnostic)

- **Identity comes from standard env vars, not code.** `service.name` comes
  from `OTEL_SERVICE_NAME`; extra resource labels from
  `OTEL_RESOURCE_ATTRIBUTES` (e.g. `deployment.environment`);
  `service.instance.id` from `DEVICE_NAME`. Never hardcode `service.name`
  as an explicit resource attribute: SDK merge precedence lets an explicit
  (or empty) value override the env var and degrade to `unknown_service`.
- **Correlation is W3C Trace Context.** The trace ID is the only
  correlator. One unit of work (e.g. one pipeline message) = one trace.
  Producers `inject` the context into a carrier that travels with the
  payload (`traceparent`, plus `baggage` for cross-cutting attributes like
  `device.name`); consumers `extract` it and parent their span to it;
  forwarders re-inject a refreshed context. Use `PRODUCER`/`CONSUMER` span
  kinds at queue boundaries, and stamp baggage values as span attributes
  downstream so they are queryable.
- **Logs ride the trace.** Bridge the platform logger into OTEL. Log
  records emitted inside an active span automatically carry
  `trace_id`/`span_id`, giving log↔trace correlation in Grafana for free.
- **Metrics vocabulary.** Histograms (unit `s`) for timings, up-down
  counters for backlog/in-flight depth, counters for events. Prefer a
  short export interval (~10s) in demo code so data appears promptly.
- **Errors are span data.** On failure: `record_exception` + ERROR status,
  then re-raise — telemetry must not replace existing error handling.
- **Graceful shutdown flushes.** On exit, `force_flush()` + `shutdown()`
  every provider, guarded so exporter errors never break app teardown.
- **Collector-side derivatives.** Recommend the Alloy
  `otelcol.connector.spanmetrics` connector for RED metrics and service
  graphs instead of hand-rolling per-operation metrics in app code.

## 2. Python-specific (`app/`, opentelemetry-python)

- **OTEL bootstrap lives in `tailucas_pylib`.** `app/__main__.py` does not
  call `setup_otel()` or import the SDK directly; provider setup, the
  experimental logs SDK (`opentelemetry.sdk._logs`,
  `...proto.grpc._log_exporter`), and exporter construction all live in the
  external `tailucas_pylib` dependency. The exporter interface to reference
  there is `LogRecordExporter`; `LogExporter` is a deprecated subclass and
  will fail type checks. Exporters are built with default constructors so
  endpoint/protocol come from the standard `OTEL_EXPORTER_OTLP_*` env vars.
- **Instruments bind at creation time.** Tracers/meters/instruments created
  before the providers are registered stay no-op forever. Create them in
  thread constructors (which run after `setup_otel()`), via the global API
  (`trace.get_tracer(APP_NAME)`, `metrics.get_meter(APP_NAME)`), or behind
  a lazy singleton (see `_get_in_flight_counter`). Note: an empty meter
  name (e.g. empty `APP_NAME`) silently yields a no-op meter.
- **Baggage is not activated by `start_as_current_span(context=...)`.**
  The `context` kwarg only controls span *parentage*; the activated
  current context is rebuilt as current+span and drops baggage entries.
  Since `inject()` serializes the current context, baggage must be merged
  onto it explicitly before injecting — see `_inject_with_baggage()`.
  Verify propagation on the wire, not by reading the API signatures.
- **`Resource.create()` precedence (SDK ≥1.44):** explicitly passed
  attributes win over `OTEL_SERVICE_NAME`. Pass only
  `service.instance.id`; let the SDK's env detector supply `service.name`.
- **Batching needs an exit flush.** `BatchSpanProcessor`,
  `BatchLogRecordProcessor`, and `PeriodicExportingMetricReader`
  (60s default interval — override with `export_interval_millis`) all
  buffer; without the shutdown flush, short runs export nothing.
- **Log bridge goes on the pylib logger** (`logging.getLogger(APP_NAME)`)
  with level `NOTSET`; the logger's own level governs. Remember
  `LOG_LEVEL` gates bridged records: with the level unset, effective
  `WARNING` silently drops `INFO` demo logs.
- **Keep mypy clean across the protocol branch:** annotate the selected
  exporters with the SDK interfaces (`SpanExporter`, `MetricExporter`,
  `LogRecordExporter`) and alias the per-protocol imports
  (`GrpcOTLPSpanExporter`/`HttpOTLPSpanExporter`).
- **ZMQ carrier:** a `dict[str, str]` field on the pickled message
  dataclass (`PipelineMessage.trace_context`) is the propagation carrier —
  plain strings pickle cleanly and accept both `traceparent` and `baggage`
  entries with no schema change.

## 3. Java-specific (`src/`, opentelemetry-java)

- **Use SDK autoconfigure** (`opentelemetry-sdk-extension-autoconfigure`):
  it reads the standard `OTEL_*` env vars and gives both protocols for
  free. Register with `GlobalOpenTelemetry.set(...)`, add only
  `service.instance.id` via `addResourceCustomizer` (never
  `service.name`). See `OtelSupport.java`.
- **Artifacts**: manage with `opentelemetry-bom` plus
  `opentelemetry-instrumentation-bom` AND `-bom-alpha` (versioned
  `<x.y.z>-alpha`; the log4j2 appender is an alpha artifact). Declare
  `opentelemetry-api-incubator` (`<sdk-version>-alpha`) explicitly —
  optional upstream, but required at runtime by autoconfigure's metrics
  wiring. Runtime-wired artifacts (exporters, sdk-logs, incubator) trip
  `dependency:analyze` "unused declared" — whitelist them in
  `ignoredUnusedDeclaredDependencies` (analysis binds to `verify`, not
  `package`).
- **`OTEL_SDK_DISABLED` suppresses export, not recording** (SDK 1.65):
  processor/exporter wiring is skipped, spans still record in memory.
  Assert on what leaves the JVM (an in-JVM `HttpServer` listener), never
  on `isRecording()`.
- **log4j2 bridging needs two steps**: declare the `<OpenTelemetry/>`
  appender in `log4j2.xml` AND call `OpenTelemetryAppender.install(sdk)`
  right after init — earlier events are queued and replayed on install.
- **Fat jars break log4j2 plugin discovery.** Build with
  `maven-shade-plugin` (keep the `jar-with-dependencies` classifier for
  the Makefile): `ServicesResourceTransformer` for OTEL SPI files, and do
  NOT rely on `AppendingTransformer` for `Log4j2Plugins.dat` — duplicate
  categories load first-wins, silently dropping later plugin packages.
  Register them deterministically with `PluginManager.addPackages(...)`
  in a static block before the first logger is created (the OTEL appender
  and JSON template layout packages).

## 4. Verification Pattern

Test against a local stub collector, not a live stack. The current Java
suite (`AppTest.java`) uses an ephemeral-port counting `HttpServer`
(HTTP/protobuf only) to assert the two export states: `OTEL_SDK_DISABLED`
suppresses export (zero calls) and an enabled SDK exports completed spans
(one or more calls). It does not decode protobufs or exercise gRPC.

The fuller pattern — recommended for derived apps — is an HTTP server on
4318 decoding `Export*ServiceRequest` protobufs (and/or a gRPC generic
handler on 4317), asserting on wire content: resource attributes per
signal, one shared trace ID with correct `parent_span_id` linkage across
stages, baggage landed as span attributes, histogram/gauge data points
present, and log records carrying nonzero `trace_id`. Exercise the error
path by forcing an exception and asserting an ERROR span with an
`exception` event. Finish with `ruff check` and `mypy` at the project
baseline.

For Java, run the **packaged shaded jar** against the stub (plugin
discovery and SPI issues only surface there, not under `exec:java`), on
both protocols. `mvn verify` must pass with `failOnWarning` dependency
analysis, and `mvn test` must stay hermetic (system properties +
`GlobalOpenTelemetry.resetForTest()`).
