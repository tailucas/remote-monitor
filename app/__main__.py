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
builtins.SENTRY_EXTRAS = []
from . import APP_NAME
class CredsConfig:
    sentry_dsn: f'opitem:"Sentry" opfield:{APP_NAME}.dsn' = None # type: ignore
    cronitor_token: f'opitem:"cronitor" opfield:.password' = None # type: ignore
# instantiate class
builtins.creds_config = CredsConfig()

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
URL_WORKER_RELAY = 'inproc://relay-{}'


class Relay(AppThread):

    def __init__(self, relay_name, io, pin):
        self._name = relay_name
        AppThread.__init__(self, name=f'{self.__class__.__name__}::{relay_name}')
        self._zmq_url = URL_WORKER_RELAY.format(relay_name)

        self._io = io
        self._pin = pin

    @property
    def zmq_url(self):
        return self._zmq_url

    def run(self):
        with exception_handler(connect_url=self._zmq_url, socket_type=zmq.PULL, and_raise=False, shutdown_on_error=True) as zmq_socket:
            while not threads.shutting_down:
                relay_ctrl = zmq_socket.recv_pyobj()
                if 'state' in relay_ctrl:
                    if relay_ctrl['state'] is True:
                        self._io.write_pin(self._pin, 1)
                        # sleep
                        if 'duration' in relay_ctrl:
                            duration = relay_ctrl['duration']
                        else:
                            duration = RELAY_DEFAULT_ACTIVE_TIME_SECONDS
                        log.info("Activating {} for {} seconds.".format(self._name, duration))
                        self._io.write_pin(self._pin, 1)
                        sleep(float(duration))
                    self._io.write_pin(self._pin, 0)


class RelayControl(AppThread):

    def __init__(self, relay_mappings):
        AppThread.__init__(self, name=self.__class__.__name__)
        # Push socket to control relays
        self._sockets = dict()
        for relay, worker_url in list(relay_mappings.items()):
            socket = zmq_socket(zmq.PUSH)
            self._sockets[relay] = socket
            socket.connect(worker_url)
        self._output_to_relay = dict()

    def visit_keys(dictionary, parent_key=''):
        for key, value in dictionary.items():
            full_key = f'{parent_key}.{key}' if parent_key else key
            if isinstance(value, dict):
                RelayControl.visit_keys(value, full_key)
            elif isinstance(value, str) or isinstance(value, int):
                log.info(f'{full_key}::{value}')
            else:
                log.info(f'{full_key}::{type(value)}')

    def run(self):
        with exception_handler(connect_url=URL_WORKER_RELAY_CTRL, socket_type=zmq.PULL, and_raise=False, shutdown_on_error=True) as zmq_socket:
            while not threads.shutting_down:
                control_payload = zmq_socket.recv_pyobj()
                if not isinstance(control_payload, dict):
                    log.info(f'Malformed event ({control_payload}); expecting dictionary.')
                    continue
                RelayControl.visit_keys(control_payload)
                if 1==1:
                    continue
                device_event = None
                for _,payload in device_event.items():
                    device_key, duration = payload['data']
                    break
                log.debug("Relay event for '{}'".format(device_key))
                if device_key not in self._output_to_relay:
                    log.debug("'{}' is not configured for relay control".format(device_key))
                    continue
                relay = self._output_to_relay[device_key]
                if relay in self._sockets:
                    log.info("'{}' => '{}'".format(device_key, relay))
                    relay_cmd = {
                        'state': True
                    }
                    if duration:
                        relay_cmd['duration'] = duration
                    self._sockets[relay].send_pyobj(relay_cmd)
                else:
                    log.error("'{}' refers to non-existent relay '{}'".format(device_key, relay))
                    post_count_metric('Errors')
        for relay, socket in self._sockets.items():
            log.info(f'Closing ZMQ socket for {relay}...')
            try:
                socket.close()
            except:
                pass

    def add_output(self, device_key, relay):
        if device_key in self._output_to_relay:
            raise RuntimeError('{} is already associated with {}. Cannot also associate {}.'.format(
                device_key,
                self._output_to_relay[device_key],
                relay))
        self._output_to_relay[device_key] = relay


if __name__ == "__main__":
    # connect to RabbitMQ
    mq_config_server = app_config.get('rabbitmq', 'server_address')
    try:
        mq_connection = pika.BlockingConnection(pika.ConnectionParameters(host=mq_config_server))
    except AMQPConnectionError:
        log.warning('RabbitMQ failure at startup.', exc_info=1)
        exit(1)
    mq_channel = mq_connection.channel()
    mq_config_exchange = app_config.get('rabbitmq', 'mq_exchange')
    mq_exchange_type = 'topic'
    mq_channel.exchange_declare(exchange=mq_config_exchange, exchange_type=mq_exchange_type)
    mq_device_topic = app_config.get('rabbitmq', 'device_topic')
    log.info(f'Using RabbitMQ server at {mq_config_server} with {mq_exchange_type} ({mq_device_topic}) exchange {mq_config_exchange}.')
    # control listener
    mq_control_listener = ZMQListener(
        zmq_url=URL_WORKER_RELAY_CTRL,
        mq_server_address=mq_config_server,
        mq_exchange_name=f'{mq_config_exchange}_control',
        mq_topic_filter=f'event.trigger.{mq_device_topic}',
        mq_exchange_type='direct')
    # process configuration
    adcs = dict()
    for adc, address in app_config.items('adc_address'):
        log.info("Configuring '{}' @ '{}'".format(adc, address))
        address = address.split(',')
        adcs[adc] = ADCPi(int(address[0], 16),
                          int(address[1], 16),
                          12)
    # hardware configuration
    ios = dict()
    for io, address in app_config.items('io_address'):
        log.info("Configuring '{}' @ '{}'".format(io, address))
        io_port = IOPi(int(address, 16))
        # set port direction to output
        io_port.set_port_direction(0, 0x00)
        io_port.set_port_direction(1, 0x00)
        # zero all pins
        io_port.write_port(0, 0x00)
        io_port.write_port(1, 0x00)
        ios[io] = io_port
    # map IO channels to relays
    relay_to_io = dict()
    for relay, address in app_config.items('relay_address'):
        io, pin = tuple(address.split(':'))
        relay_to_io[relay] = (io, int(pin))
        log.info("Mapped '{}' to IO '{}' on pin {}".format(relay, io, pin))
    # map relays to workers
    relay_workers = list()
    relay_to_worker = dict()
    # start relays
    for relay_name in list(relay_to_io.keys()):
        io, pin = relay_to_io[relay_name]
        relay = Relay(relay_name=relay_name, io=ios[io], pin=pin)
        relay.start()
        relay_workers.append(relay)
        relay_to_worker[relay_name] = relay.zmq_url

    relay_control = RelayControl(relay_mappings=relay_to_worker)
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
    for field, output_type in list(output_types.items()):
        output_location = output_locations[field]
        device_key = '{} {}'.format(output_location, output_type)
        device_info['outputs'].append({
            'type': output_type,
            'location': output_location,
            'device_key': device_key
        })
        if app_config.has_option('output_relay', field):
            relay = app_config.get('output_relay', field)
            log.info("'{}' will trigger '{}'".format(device_key, relay))
            relay_control.add_output(
                device_key=device_key,
                relay=relay)

    input_addresses = dict(app_config.items('input_address'))
    input_to_adc = dict()
    for field in input_addresses:
        adc, pin = tuple(input_addresses[field].split(':'))
        input_to_adc[field] = (adc, int(pin))
        # get the normal value
        log.info("ADC {} pin {} will detect '{}'".format(adc, pin, input_devices[field]['device_key']))

    # start relay control
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
                    log.warning('Timeout reading value from {} on pin {}.'.format(adc_name, pin), exc_info=1)
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
                        routing_key=f'event.{message_type}.{mq_device_topic}.{device_name}',
                        body=make_payload(data={
                            'inputs': payload_inputs,
                            'outputs': device_info['outputs']
                        }))
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
