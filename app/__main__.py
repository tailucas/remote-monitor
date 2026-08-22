#!/usr/bin/env python
import copy
import logging
import os
import threading
import time
from random import randint
from time import sleep

import pika
import zmq
from ADCPi import ADCPi, ADCTimeoutError
from IOPi import IOPi
from opentelemetry import metrics, propagate, trace
from opentelemetry.trace import SpanKind
from opentelemetry.trace.propagation.tracecontext import (
    TraceContextTextMapPropagator,
)
from pika.exceptions import (
    AMQPConnectionError,
    ConnectionClosedByBroker,
    StreamLostError,
)
from tailucas_pylib import APP_NAME, DEVICE_NAME, app_config, log
from tailucas_pylib.app import AppThread
from tailucas_pylib.data import make_payload
from tailucas_pylib.handler import exception_handler
from tailucas_pylib.process import SignalHandler
from tailucas_pylib.rabbit import ZMQListener
from tailucas_pylib.threads import (
    bye,
    die,
    interruptable_sleep,
    shutting_down,
    thread_nanny,
)
from tailucas_pylib.tracing import record_exception
from tailucas_pylib.zmq import zmq_term
from zmq import ContextTerminated

# FIXME: benchmark this to supply voltage using test pin or something else
ADC_SAMPLE_MAX = 5.0
HEARTBEAT_INTERVAL_SECONDS = 5
RELAY_DEFAULT_ACTIVE_TIME_SECONDS = 1
SAMPLE_INTERVAL_SECONDS = 0.1
SAMPLE_DEVIATION_TOLERANCE = 10
URL_WORKER_RELAY_CTRL = "inproc://relay-ctrl"


class Relay:
    def __init__(self, relay_name: str, io: IOPi, pin: int):
        self._name = relay_name
        self._io = io
        self._pin = pin

    def trigger(self, duration: float = RELAY_DEFAULT_ACTIVE_TIME_SECONDS) -> None:
        try:
            log.info(
                "Activating relay",
                extra={"relay_name": self._name, "duration_secs": duration},
            )
            self._io.write_pin(self._pin, 1)
            # FIXME: will hang up calling thread
            # future implementation using a ZMQ thread would be to
            # serialize all mutations on I/O but track "future" pin
            # deactivations using some kind of ZMQ poller strategy to
            # process deactivations in between legitimate mutation events.
            # Given that the controller would need access to all underlying IOPi
            # instances, RelayControl would probably need only the mappings between
            # device key and associated relay as explicitly defined in config.
            sleep(float(duration))
        finally:
            self._io.write_pin(self._pin, 0)

    def __str__(self) -> str:
        return self._name


class RelayControl(AppThread):  # type: ignore[misc]
    def __init__(self, relay_mappings: dict[str, Relay]):
        AppThread.__init__(self, name=self.__class__.__name__)
        self._relay_mappings = relay_mappings
        self._tracer = trace.get_tracer(APP_NAME)

    def run(self) -> None:
        with exception_handler(
            connect_url=URL_WORKER_RELAY_CTRL,
            socket_type=zmq.PULL,
            and_raise=False,
            shutdown_on_error=True,
        ) as zmq_socket:
            while not shutting_down:
                control_payload = zmq_socket.recv_pyobj()
                if (
                    not isinstance(control_payload, dict)
                    or "ioboard" not in control_payload
                    or "output_triggered" not in control_payload["ioboard"]
                ):
                    log.error(
                        "Malformed event payload",
                        extra={"control_payload": control_payload},
                    )
                    return
                output_trigger = control_payload["ioboard"]["output_triggered"]
                device_key = output_trigger["device_key"]
                device_params = output_trigger["device_params"]
                duration = None
                try:
                    duration = float(device_params)
                except TypeError:
                    log.warning(
                        "Cannot determine duration from device params. Using default",
                        extra={
                            "device_params": device_params,
                            "default_duration_secs": RELAY_DEFAULT_ACTIVE_TIME_SECONDS,
                        },
                    )
                log.info(
                    "Relay event",
                    extra={"device_key": device_key, "duration_secs": duration},
                )
                if device_key not in self._relay_mappings:
                    log.error(
                        "Device key does not match any relay mapping",
                        extra={
                            "device_key": device_key,
                            "relay_mappings": list(self._relay_mappings.keys()),
                        },
                    )
                    continue
                relay = self._relay_mappings[device_key]
                log.debug(
                    "Device key mapped to relay",
                    extra={"device_key": device_key, "relay": str(relay)},
                )
                traceparent = control_payload["ioboard"].get("traceparent")
                context = None
                if traceparent:
                    context = TraceContextTextMapPropagator().extract(
                        {"traceparent": str(traceparent)}
                    )
                with self._tracer.start_as_current_span(
                    "relay.trigger",
                    context=context,
                    kind=SpanKind.CONSUMER,
                ) as span:
                    span.set_attribute("device_key", device_key)
                    if duration:
                        relay.trigger(duration=duration)
                    else:
                        relay.trigger()


def main() -> None:
    # connect to RabbitMQ
    mq_config_server = app_config.get("rabbitmq", "server_address")
    try:
        mq_connection = pika.BlockingConnection(
            pika.ConnectionParameters(host=mq_config_server)
        )
    except AMQPConnectionError:
        log.warning("RabbitMQ failure at startup.", exc_info=True)
        exit(1)
    mq_channel = mq_connection.channel()
    mq_config_exchange = app_config.get("rabbitmq", "mq_exchange")
    mq_exchange_type = "topic"
    mq_channel.exchange_declare(
        exchange=mq_config_exchange, exchange_type=mq_exchange_type
    )
    mq_device_topic_suffix = app_config.get("rabbitmq", "device_topic")
    mq_device_topic = f"event.trigger.{mq_device_topic_suffix}"
    log.info(
        "Using RabbitMQ server",
        extra={
            "server_address": mq_config_server,
            "exchange_type": mq_exchange_type,
            "device_topic": mq_device_topic,
            "exchange_name": mq_config_exchange,
        },
    )
    # control listener
    mq_control_listener = ZMQListener(
        zmq_url=URL_WORKER_RELAY_CTRL,
        mq_server_address=mq_config_server,
        mq_exchange_name=f"{mq_config_exchange}_control",
        mq_topic_filter=mq_device_topic,
        mq_exchange_type="direct",
    )
    # process configuration
    adcs: dict[str, ADCPi] = {}
    for adc, address in app_config.items("adc_address"):
        log.info("Configuring ADC", extra={"adc": adc, "address": address})
        address = address.split(",")
        adcs[adc] = ADCPi(int(address[0], 16), int(address[1], 16), 12)
    # hardware configuration
    ios: dict[str, IOPi] = {}
    for io, address in app_config.items("io_address"):
        log.info("Configuring I/O", extra={"io": io, "address": address})
        io_port = IOPi(int(address, 16))
        # set port direction to output
        io_port.set_port_direction(0, 0x00)
        io_port.set_port_direction(1, 0x00)
        # zero all pins
        io_port.write_port(0, 0x00)
        io_port.write_port(1, 0x00)
        ios[io] = io_port
    # map IO channels to relays
    relay_to_io: dict[str, tuple[str, int]] = {}
    for relay_name, address in app_config.items("relay_address"):
        io, pin = tuple(address.split(":"))
        relay_to_io[relay_name] = (io, int(pin))
        log.info(
            "Mapped relay to IO",
            extra={"relay_name": relay_name, "io": io, "pin": pin},
        )
    # map relays to workers
    relays: dict[str, Relay] = {}
    # start relays
    for relay_name in list(relay_to_io.keys()):
        io, pin = relay_to_io[relay_name]
        relay = Relay(relay_name=relay_name, io=ios[io], pin=pin)
        relays[relay_name] = relay
        log.info(
            "Mapped relay instance to IO",
            extra={"relay_name": relay_name, "io": str(ios[io]), "pin": pin},
        )
    # map application configuration
    input_types = dict(app_config.items("input_type"))
    # name overrides location name
    input_names = dict(app_config.items("input_name"))
    input_locations = dict(app_config.items("input_location"))
    # construct the device representation
    input_devices = {}
    output_types = dict(app_config.items("output_type"))
    output_locations = dict(app_config.items("output_location"))
    device_info: dict[str, list[dict[str, str]]] = {}
    device_info["inputs"] = []
    for field, input_type in list(input_types.items()):
        input_name = input_names[field]
        input_location = input_locations[field]
        device_description = {
            "name": input_name,
            "type": input_type,
            "location": input_location,
            "device_key": f"{input_name} {input_type} ({input_location})",
            "device_label": f"{input_name} {input_type}",
        }
        device_info["inputs"].append(device_description)
        input_devices[field] = device_description
    device_info["outputs"] = []
    device_to_relay: dict[str, Relay] = {}
    for field, output_type in list(output_types.items()):
        output_location = output_locations[field]
        device_key = f"{output_location} {output_type}"
        device_info["outputs"].append(
            {"type": output_type, "location": output_location, "device_key": device_key}
        )
        if app_config.has_option("output_relay", field):
            relay_name = app_config.get("output_relay", field)
            device_to_relay[device_key] = relays[relay_name]
            log.info(
                "Device will trigger relay",
                extra={"device_key": device_key, "relay_name": relay_name},
            )
    input_addresses = dict(app_config.items("input_address"))
    input_to_adc: dict[str, tuple[str, int]] = {}
    for field in input_addresses:
        adc, pin = tuple(input_addresses[field].split(":"))
        input_to_adc[field] = (adc, int(pin))
        # get the normal value
        device_key = input_devices[field]["device_key"]
        log.info(
            "ADC pin will detect device",
            extra={"adc": adc, "pin": pin, "device_key": device_key},
        )
    # start relay control
    relay_control = RelayControl(relay_mappings=device_to_relay)
    relay_control.start()
    mq_control_listener.start()

    samples_processed = 0

    tracer = trace.get_tracer(APP_NAME)
    meter = metrics.get_meter(APP_NAME)
    voltage_histogram = meter.create_histogram(
        "read_voltage.duration",
        unit="ms",
        description="Time taken to read a voltage sample from an ADC",
    )

    input_normal_values = dict(app_config.items("input_normal_values"))
    tamper_label = app_config.get("app", "tamper_label")
    input_tamper_values = dict(app_config.items("input_tamper_values"))

    # must be main thread
    signal_handler = SignalHandler()
    # start the nanny
    nanny = threading.Thread(
        name="nanny", target=thread_nanny, args=(signal_handler,), daemon=True
    )
    nanny.start()
    try:
        # startup completed
        # back to INFO logging
        log.setLevel(logging.INFO)
        env_vars = list(os.environ)
        env_vars.sort()
        log.info(
            "Startup complete",
            extra={"env_var_count": len(env_vars), "env_vars": env_vars},
        )
        last_upload = 0.0
        device_history: dict[str, tuple[float, float, str | None]] = {}
        last_triggered_keys: set[str] = set()
        active_span: trace.Span | None = None
        while not shutting_down:
            triggered_devices: dict[str, dict[str, str]] = {}
            output_samples: dict[str, int] = {}
            for i in list(input_to_adc.keys()):
                adc_name, pin = input_to_adc[i]
                try:
                    sample_start = time.perf_counter()
                    sampled_value = adcs[adc_name].read_voltage(pin)
                    voltage_histogram.record(
                        (time.perf_counter() - sample_start) * 1000,
                        attributes={"adc_name": adc_name, "pin": pin},
                    )
                except ADCTimeoutError:
                    log.warning(
                        "Timeout reading value from ADC",
                        exc_info=True,
                        extra={"adc_name": adc_name, "pin": pin},
                    )
                    interruptable_sleep.wait(1)
                    continue
                normalized_value = (sampled_value / ADC_SAMPLE_MAX) * 100
                input_value = int(input_normal_values[i])
                device_key = input_devices[i]["device_key"]
                samples_processed += 1
                if randint(0, 1000) < SAMPLE_INTERVAL_SECONDS * 1000:
                    log.debug(
                        "Comparing ADC sample to normal value",
                        extra={
                            "adc_name": adc_name,
                            "pin": pin,
                            "normalized_value": normalized_value,
                            "sampled_value_v": sampled_value,
                            "input_value": input_value,
                            "device_key": device_key,
                            "tolerance": SAMPLE_DEVIATION_TOLERANCE,
                        },
                    )
                if abs(normalized_value - input_value) <= SAMPLE_DEVIATION_TOLERANCE:
                    # forget that this device was active
                    if device_key in device_history:
                        log.debug(
                            "Device is no longer active",
                            extra={"device_key": device_key},
                        )
                        del device_history[device_key]
                    # nothing else to unset here, next input now
                    continue
                # a device has now gone out of normal range
                device_event_distinction = device_key
                output_samples[device_key] = int(normalized_value)
                input_device = copy.copy(input_devices[i])
                input_device["sample_value"] = int(normalized_value)
                input_device["state"] = "OK"
                event_detail = None
                if i in input_tamper_values:
                    tamper_value = int(input_tamper_values[i])
                    if (
                        abs(normalized_value - tamper_value)
                        <= SAMPLE_DEVIATION_TOLERANCE
                    ):
                        event_detail = tamper_label
                        device_event_distinction = f"{device_key} {tamper_label}"
                # now include the event detail
                input_device["event_detail"] = event_detail
                # determine whether the value has changed
                if device_key in device_history:
                    historic_value, sampled_at, historic_detail = device_history[
                        device_key
                    ]
                    # has the value stayed the same?
                    if (
                        abs(normalized_value - historic_value)
                        <= SAMPLE_DEVIATION_TOLERANCE
                        and event_detail == historic_detail
                    ):
                        # sample to avoid log spam
                        if randint(0, 1000) < SAMPLE_INTERVAL_SECONDS * 1000:
                            log.debug(
                                "Debouncing device event",
                                extra={
                                    "event_distinction": device_event_distinction,
                                    "event_detail": event_detail,
                                    "active_secs_ago": int(time.time() - sampled_at),
                                },
                            )
                        continue
                # update the device history and treat as active
                device_history[device_key] = (
                    normalized_value,
                    time.time(),
                    event_detail,
                )
                # set the state to 'active'
                input_device["state"] = "triggered"
                triggered_devices[device_key] = input_device
                log.info(
                    "Device event triggered",
                    extra={
                        "device_event_distinction": device_event_distinction,
                        "event_detail": event_detail,
                        "sampled_value": normalized_value,
                    },
                )
            # include triggered inputs with configured inputs
            payload_inputs: list[dict[str, str]] = []
            for device_input in device_info["inputs"]:
                device_key = device_input["device_key"]
                if device_key in triggered_devices:
                    payload_inputs.append(triggered_devices[device_key])
                else:
                    payload_inputs.append(device_input)

            # trace management
            current_triggered_keys = set(triggered_devices.keys())
            if current_triggered_keys != last_triggered_keys:
                if active_span:
                    active_span.end()
                    active_span = None

                if current_triggered_keys:
                    active_span = tracer.start_span(
                        "publish device event", kind=SpanKind.PRODUCER
                    )
                    active_span.set_attribute("messaging.system", "rabbitmq")
                    active_span.set_attribute("messaging.destination", mq_config_exchange)
                    active_span.set_attribute("messaging.destination_kind", "topic")
                    active_span.set_attribute("messaging.operation", "publish")

                last_triggered_keys = current_triggered_keys

            inactivity = time.time() - last_upload
            if triggered_devices or inactivity > HEARTBEAT_INTERVAL_SECONDS:
                message_type = "notify"
                mq_message_type = "input_active"
                if not triggered_devices:
                    message_type = "heartbeat"
                    mq_message_type = message_type

                routing_key = (
                    f"event.{message_type}."
                    f"{mq_device_topic_suffix}.{DEVICE_NAME}"
                )

                # if it's a heartbeat, it always gets its own span
                # if it's a notification, it uses the active span (which persists if the key set is unchanged)
                span_to_use = active_span
                heartbeat_span = None
                if not triggered_devices:
                    heartbeat_span = tracer.start_span(
                        "publish device event (heartbeat)", kind=SpanKind.PRODUCER
                    )
                    heartbeat_span.set_attribute("messaging.system", "rabbitmq")
                    heartbeat_span.set_attribute(
                        "messaging.destination", mq_config_exchange
                    )
                    heartbeat_span.set_attribute("messaging.destination_kind", "topic")
                    heartbeat_span.set_attribute("messaging.operation", "publish")
                    span_to_use = heartbeat_span

                if span_to_use:
                    span_to_use.set_attribute("messaging.routing_key", routing_key)
                    carrier: dict[str, str] = {}
                    # use the specific span's context for injection
                    with trace.use_span(span_to_use, set_attribute_on_status_code=False):
                        propagate.inject(carrier)

                    try:
                        mq_channel.basic_publish(
                            exchange=mq_config_exchange,
                            routing_key=routing_key,
                            body=make_payload(
                                data={
                                    "inputs": payload_inputs,
                                    "outputs": device_info["outputs"],
                                    "message_type": mq_message_type,
                                    "traceparent": carrier["traceparent"],
                                }
                            ),
                        )
                    except (
                        AMQPConnectionError,
                        ConnectionClosedByBroker,
                        StreamLostError,
                    ) as e:
                        record_exception(e)
                        if heartbeat_span:
                            heartbeat_span.end()
                        raise RuntimeWarning() from e
                    finally:
                        if heartbeat_span:
                            heartbeat_span.end()

                    last_upload = time.time()
            interruptable_sleep.wait(SAMPLE_INTERVAL_SECONDS)
        raise RuntimeWarning("Shutting down...")
    except (KeyboardInterrupt, RuntimeWarning, ContextTerminated):
        if active_span:
            active_span.end()
        die()
        log.info("Shutting down RabbitMQ control listener...")
        mq_control_listener.stop()
        log.info("Shutting down RabbitMQ worker...")
        try:
            mq_connection.close()
        except (AMQPConnectionError, ConnectionClosedByBroker, StreamLostError) as e:
            log.warning(
                "Problem when closing RabbitMQ connection", extra={"error": str(e)}
            )
    finally:
        zmq_term()
    bye()


if __name__ == "__main__":
    main()
