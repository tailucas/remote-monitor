#!/usr/bin/env python
import builtins
import copy
import logging.handlers
import pika
import threading
import time
import zmq

from ADCPi import ADCPi # type: ignore
from ADCPi import TimeoutError
from IOPi import IOPi # type: ignore

from pathlib import Path
from pika.exceptions import AMQPConnectionError, StreamLostError, ConnectionClosedByBroker
from random import randint
from sentry_sdk.integrations.logging import ignore_logger
from time import sleep
from zmq import ContextTerminated, ZMQError

import os.path

# setup builtins used by pylib init
builtins.SENTRY_EXTRAS = [] # type: ignore
from . import APP_NAME
class CredsConfig:
    sentry_dsn: f'opitem:"Sentry" opfield:{APP_NAME}.dsn' = None # type: ignore
    cronitor_token: f'opitem:"cronitor" opfield:.password' = None # type: ignore
# instantiate class
builtins.creds_config = CredsConfig() # type: ignore

from tailucas_pylib import app_config, \
    device_name, \
    log

from tailucas_pylib.data import make_payload
from tailucas_pylib.aws.metrics import post_count_metric
from tailucas_pylib.rabbit import ZMQListener
from tailucas_pylib.process import SignalHandler
from tailucas_pylib import threads
from tailucas_pylib.threads import thread_nanny, die, bye
from tailucas_pylib.app import AppThread
from tailucas_pylib.zmq import zmq_term, zmq_socket
from tailucas_pylib.handler import exception_handler

from typing import Dict

# Reduce Sentry noise from pika loggers
ignore_logger('pika.adapters.base_connection')
ignore_logger('pika.adapters.blocking_connection')
ignore_logger('pika.adapters.utils.connection_workflow')
ignore_logger('pika.adapters.utils.io_services_utils')
ignore_logger('pika.channel')


# FIXME: benchmark this to supply voltage using test pin or something else
ADC_SAMPLE_MAX = 5.0
HEARTBEAT_INTERVAL_SECONDS = 5
RELAY_DEFAULT_ACTIVE_TIME_SECONDS = 1
SAMPLE_INTERVAL_SECONDS = 0.1
SAMPLE_DEVIATION_TOLERANCE = 10
URL_WORKER_RELAY_CTRL = 'inproc://relay-ctrl'


class Relay(object):

    def __init__(self, relay_name: str, io: IOPi, pin: int):
        self._name = relay_name
        self._io = io
        self._pin = pin

    def trigger(self, duration: float=RELAY_DEFAULT_ACTIVE_TIME_SECONDS):
        try:
            log.info("Activating {} for {} seconds.".format(self._name, duration))
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

    def __str__(self):
        return self._name


class RelayControl(AppThread):

    def __init__(self, relay_mappings: Dict[str, Relay]):
        AppThread.__init__(self, name=self.__class__.__name__)
        self._relay_mappings = relay_mappings

    def run(self):
        with exception_handler(connect_url=URL_WORKER_RELAY_CTRL, socket_type=zmq.PULL, and_raise=False, shutdown_on_error=True) as zmq_socket:
            while not threads.shutting_down:
                control_payload = zmq_socket.recv_pyobj()
                if not isinstance(control_payload, dict) or 'ioboard' not in control_payload or 'output_triggered' not in control_payload['ioboard']:
                    log.error(f'Malformed event payload {control_payload}.')
                    return
                output_trigger = control_payload['ioboard']['output_triggered']
                device_key = output_trigger['device_key']
                device_params = output_trigger['device_params']
                duration = None
                try:
                    duration = float(device_params)
                except TypeError:
                    log.warn(f'Cannot determine duration from {device_params}, using default of {RELAY_DEFAULT_ACTIVE_TIME_SECONDS}s.')
                log.info(f'Relay event for {device_key} with duration {duration}')
                if device_key not in self._relay_mappings:
                    log.error(f'{device_key} does not match any of {self._relay_mappings.keys()}')
                    post_count_metric('Errors')
                    continue
                relay = self._relay_mappings[device_key]
                log.info(f'{device_key} => {relay!s}')
                if duration:
                    relay.trigger(duration=duration)
                else:
                    relay.trigger()


if __name__ == "__main__":
    # connect to RabbitMQ
    mq_config_server = app_config.get('rabbitmq', 'server_address')
    try:
        mq_connection = pika.BlockingConnection(pika.ConnectionParameters(host=mq_config_server))
    except AMQPConnectionError:
        log.warning('RabbitMQ failure at startup.', exc_info=True)
        exit(1)
    mq_channel = mq_connection.channel()
    mq_config_exchange = app_config.get('rabbitmq', 'mq_exchange')
    mq_exchange_type = 'topic'
    mq_channel.exchange_declare(exchange=mq_config_exchange, exchange_type=mq_exchange_type)
    mq_device_topic_suffix = app_config.get('rabbitmq', 'device_topic')
    mq_device_topic = f'event.trigger.{mq_device_topic_suffix}'
    log.info(f'Using RabbitMQ server at {mq_config_server} with {mq_exchange_type} ({mq_device_topic}) exchange {mq_config_exchange}.')
    # control listener
    mq_control_listener = ZMQListener(
        zmq_url=URL_WORKER_RELAY_CTRL,
        mq_server_address=mq_config_server,
        mq_exchange_name=f'{mq_config_exchange}_control',
        mq_topic_filter=mq_device_topic,
        mq_exchange_type='direct')
    # process configuration
    adcs: Dict[str, ADCPi] = dict()
    for adc, address in app_config.items('adc_address'):
        log.info(f'Configuring ADC {adc} @ {address}')
        address = address.split(',')
        adcs[adc] = ADCPi(int(address[0], 16),
                          int(address[1], 16),
                          12)
    # hardware configuration
    ios: Dict[str, IOPi] = dict()
    for io, address in app_config.items('io_address'):
        log.info(f'Configuring I/O {io} @ {address}')
        io_port = IOPi(int(address, 16))
        # set port direction to output
        io_port.set_port_direction(0, 0x00)
        io_port.set_port_direction(1, 0x00)
        # zero all pins
        io_port.write_port(0, 0x00)
        io_port.write_port(1, 0x00)
        ios[io] = io_port
    # map IO channels to relays
    relay_to_io: Dict[str, tuple[str, int]] = dict()
    for relay_name, address in app_config.items('relay_address'):
        io, pin = tuple(address.split(':'))
        relay_to_io[relay_name] = (io, int(pin))
        log.info(f'Mapped {relay_name} to IO {io} on pin {pin}')
    # map relays to workers
    relays: Dict[str, Relay] = dict()
    # start relays
    for relay_name in list(relay_to_io.keys()):
        io, pin = relay_to_io[relay_name]
        relay = Relay(relay_name=relay_name, io=ios[io], pin=pin)
        relays[relay_name] = relay
        log.info(f'Mapped relay {relay_name} to IO {ios[io]} on pin {pin}')
    # map application configuration
    input_types = dict(app_config.items('input_type'))
    # name overrides location name
    input_names = dict(app_config.items('input_name'))
    input_locations = dict(app_config.items('input_location'))
    # construct the device representation
    input_devices = dict()
    output_types = dict(app_config.items('output_type'))
    output_locations = dict(app_config.items('output_location'))
    device_info = dict()
    device_info['inputs'] = list()
    for field, input_type in list(input_types.items()):
        input_name = input_names[field]
        input_location = input_locations[field]
        device_description = {
            'name': input_name,
            'type': input_type,
            'location': input_location,
            'device_key': '{} {} ({})'.format(input_name, input_type, input_location),
            'device_label': '{} {}'.format(input_name, input_type)
        }
        device_info['inputs'].append(device_description)
        input_devices[field] = device_description
    device_info['outputs'] = list()
    device_to_relay: Dict[str, Relay] = dict()
    for field, output_type in list(output_types.items()):
        output_location = output_locations[field]
        device_key = '{} {}'.format(output_location, output_type)
        device_info['outputs'].append({
            'type': output_type,
            'location': output_location,
            'device_key': device_key
        })
        if app_config.has_option('output_relay', field):
            relay_name = app_config.get('output_relay', field)
            device_to_relay[device_key] = relays[relay_name]
            log.info(f'{device_key} will trigger {relay_name}')
    input_addresses = dict(app_config.items('input_address'))
    input_to_adc = dict()
    for field in input_addresses:
        adc, pin = tuple(input_addresses[field].split(':'))
        input_to_adc[field] = (adc, int(pin))
        # get the normal value
        device_key = input_devices[field]['device_key']
        log.info(f'ADC {adc} pin {pin} will detect {device_key}')
    # start relay control
    relay_control = RelayControl(relay_mappings=device_to_relay)
    relay_control.start()
    mq_control_listener.start()

    samples_processed = 0

    input_normal_values = dict(app_config.items('input_normal_values'))
    tamper_label = app_config.get('app', 'tamper_label')
    input_tamper_values = dict(app_config.items('input_tamper_values'))

    # must be main thread
    signal_handler = SignalHandler()
    # start the nanny
    nanny = threading.Thread(name='nanny', target=thread_nanny, args=(signal_handler,), daemon=True)
    nanny.start()
    try:
        # startup completed
        # back to INFO logging
        log.setLevel(logging.INFO)
        env_vars = list(os.environ)
        env_vars.sort()
        log.info(f'Startup complete with {len(env_vars)} environment variables visible: {env_vars}.')
        last_upload = 0
        device_history = dict()
        while not threads.shutting_down:
            triggered_devices = dict()
            output_samples = dict()
            for i in list(input_to_adc.keys()):
                adc_name, pin = input_to_adc[i]
                try:
                    sampled_value = adcs[adc_name].read_voltage(pin)
                except TimeoutError:
                    log.warning('Timeout reading value from {} on pin {}.'.format(adc_name, pin), exc_info=True)
                    threads.interruptable_sleep.wait(1)
                    continue
                normalized_value = (sampled_value / ADC_SAMPLE_MAX) * 100
                input_value = int(input_normal_values[i])
                device_key = input_devices[i]['device_key']
                device_type = input_devices[i]['type']
                samples_processed += 1
                if randint(0, 1000) < SAMPLE_INTERVAL_SECONDS * 1000:
                    log.debug('Comparing {}.{}={} ({}v) '
                              'to {} ({}) (tolerance: {})'.format(adc_name,
                                                                  pin,
                                                                  normalized_value,
                                                                  sampled_value,
                                                                  input_value,
                                                                  device_key,
                                                                  SAMPLE_DEVIATION_TOLERANCE))
                if abs(normalized_value - input_value) <= SAMPLE_DEVIATION_TOLERANCE:
                    # forget that this device was active
                    if device_key in device_history:
                        log.debug("'{}' is no longer active.".format(device_key))
                        del device_history[device_key]
                    # nothing else to unset here, next input now
                    continue
                # a device has now gone out of normal range
                device_event_distinction = device_key
                output_samples[device_key] = int(normalized_value)
                input_device = copy.copy(input_devices[i])
                input_device['sample_value'] = int(normalized_value)
                input_device['state'] = 'OK'
                event_detail = None
                if i in input_tamper_values:
                    tamper_value = int(input_tamper_values[i])
                    if abs(normalized_value - tamper_value) <= SAMPLE_DEVIATION_TOLERANCE:
                        event_detail = tamper_label
                        device_event_distinction = '{} {}'.format(device_key, tamper_label)
                # now include the event detail
                input_device['event_detail'] = event_detail
                # determine whether the value has changed
                if device_key in device_history:
                    historic_value, sampled_at, historic_detail = device_history[device_key]
                    # has the value stayed the same?
                    if abs(normalized_value - historic_value) <= SAMPLE_DEVIATION_TOLERANCE and event_detail == historic_detail:
                        # sample to avoid log spam
                        if randint(0, 1000) < SAMPLE_INTERVAL_SECONDS * 1000:
                            log.debug("Debouncing '{}' (detail: {}) activated {} seconds "
                                      "ago.".format(device_event_distinction, event_detail,
                                                    int(time.time() - sampled_at)))
                        continue
                # update the device history and treat as active
                device_history[device_key] = (normalized_value, time.time(), event_detail)
                # set the state to 'active'
                input_device['state'] = 'triggered'
                triggered_devices[device_key] = input_device
                log.info("'{}' (detail: {}, sampled: {})".format(device_event_distinction, event_detail, normalized_value))
            # include triggered inputs with configured inputs
            payload_inputs = list()
            for device_input in device_info['inputs']:
                device_key = device_input['device_key']
                if device_key in triggered_devices:
                    payload_inputs.append(triggered_devices[device_key])
                else:
                    payload_inputs.append(device_input)
            inactivity = time.time() - last_upload
            if triggered_devices or inactivity > HEARTBEAT_INTERVAL_SECONDS:
                message_type = 'notify'
                if not triggered_devices:
                    message_type = 'heartbeat'
                try:
                    mq_channel.basic_publish(
                        exchange=mq_config_exchange,
                        routing_key=f'event.{message_type}.{mq_device_topic_suffix}.{device_name}',
                        body=make_payload(data={
                            'inputs': payload_inputs,
                            'outputs': device_info['outputs']
                        })) # type: ignore
                    last_upload = time.time()
                except (AMQPConnectionError, ConnectionClosedByBroker, StreamLostError) as e:
                    raise RuntimeWarning() from e
            threads.interruptable_sleep.wait(SAMPLE_INTERVAL_SECONDS)
        raise RuntimeWarning("Shutting down...")
    except(KeyboardInterrupt, RuntimeWarning, ContextTerminated) as e:
        die()
        message = "Shutting down {}..."
        log.info(message.format('RabbitMQ control'))
        mq_control_listener.stop()
        log.info(message.format('RabbitMQ worker'))
        try:
            mq_connection.close()
        except (AMQPConnectionError, ConnectionClosedByBroker, StreamLostError) as e:
            log.warning(f'When closing: {e!s}')
    finally:
        zmq_term()
    bye()
