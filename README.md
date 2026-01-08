<a name="readme-top"></a>

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]

## About The Project

### Overview

**Note 1**: See my write-up on [IoT with Balena Cloud][blog-url] for architectural context and operational experience with IoT deployment patterns.

**Note 2**: This project **extends the architecture patterns** from [base-app][baseapp-url] but does **not directly inherit the Dockerfile** due to its specific hardware deployment requirements with Balena Cloud. Instead, it uses a custom Debian-based image with equivalent support infrastructure (1Password Secrets, Sentry, ZeroMQ, RabbitMQ integration).

### Core Functionality

This is a **430-line Python application** designed to interface with the [Raspberry Pi][rpi-url] GPIO system via I2C-connected hardware:
- **Analog-to-Digital Converter (ADC)** boards for sensing analog input values
- **I/O Expander (IOPi)** boards for controlling output signals/relays

The application continuously samples ADC inputs, applies configurable thresholds and tamper detection, debounces rapid changes, and publishes events to RabbitMQ for downstream processing. Output events from RabbitMQ trigger relay control via GPIO. The project is optimized for **Balena Cloud deployment** on Raspberry Pi and similar ARM devices, providing automated updates and remote management.

**Key Features:**

* **Continuous ADC Sampling**: Real-time monitoring of analog inputs from multiple ADC boards (I2C addresses configurable)
* **Relay Control**: GPIO-based relay triggering via I/O expander boards with configurable activation duration (default 1 second)
* **Threshold-Based Detection**: Configurable normal and tamper value thresholds with configurable tolerance window (default ±10%)
* **Debouncing**: Prevents chattering by tracking device history and requiring stable readings
* **RabbitMQ Integration**: Publishes device state changes (notify) and periodic heartbeats to RabbitMQ topic exchange
* **Remote Control**: Listens on RabbitMQ control exchange for output relay trigger commands with dynamic duration parameters
* **Balena Cloud Deployment**: Optimized for automated deployment, updates, and remote management via Balena Cloud
* **Tailscale Integration**: Built-in WireGuard VPN client for secure remote access
* **Health Monitoring**: Cron-based heartbeat to Healthchecks.io (every 5 minutes) and Cronitor monitoring
* **Sentry Integration**: Production error tracking with thread-safe instrumentation
* **Supervisor Process Management**: Multi-process orchestration for application and cron jobs

### Architecture & Design

This 430-line Python application (`app/__main__.py`) demonstrates patterns for building real-time hardware monitoring systems with inter-process communication:

**Core Components:**

* **`ADCPi` / `IOPi`** (ABElectronics libraries): Direct I2C interface to ADC and I/O expander boards configured via `adc_address` and `io_address` sections
* **`Relay`** (line 64): Wrapper around a single I/O pin that triggers pin HIGH for a specified duration then returns to LOW
* **`RelayControl`** (line 90): `AppThread` that runs a ZeroMQ PULL socket (`inproc://relay-ctrl`) to receive relay trigger payloads and dispatch to appropriate `Relay` instances
* **Main Loop** (line 286): Samples all configured ADC inputs, normalizes voltage readings (0-5V → 0-100%), applies thresholds, detects tamper states, and publishes to RabbitMQ on state change or heartbeat interval
* **Message Structures**: Device events include location, type, sample value, state (OK/triggered), and optional event detail (tamper label)
* **ZMQListener** (from pylib): Background thread monitoring RabbitMQ control exchange for relay commands, forwards to RelayControl via ZMQ

**Sampling & Thresholding Flow:**

1. Read voltage from ADC pin → normalize to 0-100%
2. Compare to configured `input_normal_values` with tolerance window
3. Track state in `device_history` (value, timestamp, detail)
4. If out of range: check for tamper condition against `input_tamper_values`
5. Debounce: ignore if history shows no value/detail change
6. Publish state via RabbitMQ to `event.notify.{topic}.{device_name}`
7. Heartbeat published every 5 seconds if no state change

**Configuration Pattern:**

- INI-format `config/app.conf` with variable interpolation from Balena Fleet variables via `%(VARIABLE_NAME)s` syntax
- 7 analog inputs (I1-I7) mapped to ADC pins via `input_address`, with locations/types/thresholds from Fleet variables
- 4 output devices (O1-O4) mapped to relays via `output_relay` mapping
- Feature flags (not currently used, but supported in config)

**Technology Patterns:**

- **ABElectronics**: Python libraries for ADS1115 ADC and MCP23017 I/O expander
- **pika**: RabbitMQ client with exception handling for connection resilience
- **ZeroMQ (inproc)**: Thread-safe inter-component messaging between main loop and RelayControl
- **Balena SDK**: Device management, supervisor config, Balena-specific environment variables
- **Tailscale**: WireGuard VPN for remote access without public IP exposure
- **Sentry SDK**: Production error tracking with async integration
- **tailucas-pylib**: Shared patterns (CredsConfig, SignalHandler, AppThread, ZMQListener, thread_nanny)

See [tailucas-pylib][pylib-url] for shared patterns and utilities.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Built With

Technologies that help make this project useful:

[![1Password][1p-shield]][1p-url]
[![RabbitMQ][rabbit-shield]][rabbit-url]
[![Raspberry Pi][rpi-shield]][rpi-url]
[![Python][python-shield]][python-url]
[![Sentry][sentry-shield]][sentry-url]
[![ZeroMQ][zmq-shield]][zmq-url]

Also:

* [Balena Cloud][balena-cloud-url]
* [ABElectronics Python Libraries][abelectronics-url]
* [Tailscale][tailscale-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>


<!-- GETTING STARTED -->
## Getting Started

Here is some detail about the intended use of this package.

### Prerequisites

This project requires:

* **[1Password Secrets Automation][1p-url]**: Runtime credential and configuration management (paid with free tier)
* **[Sentry][sentry-url]**: Error tracking and monitoring (free tier available)
* **[RabbitMQ][rabbit-url]**: Message broker for device communication (self-hosted or managed service)
* **[Balena Cloud Account][balena-cloud-url]**: IoT device management and automated deployment (free tier for 1 device)
* **Raspberry Pi** or similar ARM device registered with Balena Cloud
* **I2C Hardware**: ADC boards (ADS1115 or compatible) and I/O Expander boards (MCP23017 or compatible)

Optional services:
* **[Healthchecks.io][healthchecks-url]**: Health check monitoring (free tier available)
* **[Cronitor][cronitor-url]**: Cron job and process monitoring
* **[Tailscale][tailscale-url]**: VPN for remote device access (free tier available)

### Required Tools

Install these tools before setting up the project:

* **`balena-cli`**: Balena deployment tool - https://docs.balena.io/reference/balena-cli/
* **`docker`** and **`docker-compose`**: Container runtime - https://docs.docker.com/engine/install/
* **`task`**: Build orchestration - https://taskfile.dev/installation/#install-script
* **`uv`**: Python package manager - https://docs.astral.sh/uv/getting-started/installation/

### Installation

:stop_sign: **1Password Secrets Automation Required**: This project stores all configuration and credentials via [1Password Secrets Automation][1p-url]. A 1Password Connect server must be running in your environment. If you prefer not to use this, fork the project and modify the credential loading logic in `app/__main__.py` (lines 137-153).

#### Step 1: Configure 1Password Secrets

Your 1Password Secrets Automation vault must contain an entry called `ENV.remote-monitor` with the following configuration variables:

| Variable | Purpose | Example |
|---|---|---|
| `APP_NAME` | Application identifier for logging | `remote-monitor` |
| `AWS_CONFIG_FILE` | AWS config file path (legacy, required for build) | `/home/app/.aws/config` |
| `AWS_DEFAULT_REGION` | AWS region (legacy, required for build) | `us-east-1` |
| `CRONITOR_MONITOR_KEY` | Cronitor health check API key | *specific to your account* |
| `DEVICE_NAME` | Container hostname / device identifier | `remote-monitor` |
| `HC_PING_URL` | Healthchecks.io ping URL for 5-minute heartbeat | *specific to your check* |
| `INPUT_1_LOCATION` through `INPUT_7_LOCATION` | ADC input location names | e.g., "Front Door", "Back Gate" |
| `INPUT_1_NAME` through `INPUT_7_NAME` | ADC input device names | e.g., "Contact Sensor", "Motion" |
| `INPUT_1_TYPE` through `INPUT_7_TYPE` | ADC input device types | e.g., "Sensor", "Switch" |
| `INPUT_1_VALUE_NORMAL` through `INPUT_7_VALUE_NORMAL` | Normal ADC reading in 0-100 scale | `50` |
| `INPUT_1_VALUE_TAMPER` through `INPUT_7_VALUE_TAMPER` | Tamper detection ADC reading (optional) | `75` |
| `INPUT_TAMPER_LABEL` | Label for tamper event detail | `"TAMPERED"` |
| `OP_CONNECT_HOST` | 1Password Connect server URL | `http://1password-connect:8080` |
| `OP_CONNECT_TOKEN` | 1Password Connect API token | *specific to your server* |
| `OP_VAULT` | 1Password vault ID | *specific to your vault* |
| `OUTPUT_1_LOCATION` through `OUTPUT_4_LOCATION` | Relay output location names | e.g., "Front Light", "Gate Lock" |
| `OUTPUT_1_TYPE` through `OUTPUT_4_TYPE` | Relay output device types | e.g., "Relay", "Switch" |
| `OUTPUT_1_RELAY` through `OUTPUT_4_RELAY` | Relay name to trigger for output | `relay1`, `relay2`, etc. |
| `RABBITMQ_DEVICE_TOPIC` | RabbitMQ device topic suffix | `ioboard` |
| `RABBITMQ_EXCHANGE` | RabbitMQ exchange name | `home_automation` |
| `RABBITMQ_SERVER_ADDRESS` | RabbitMQ broker IP/hostname | `192.168.1.100` |

**Additional Credentials** (stored separately in 1Password):
- `Cronitor/password`: Cronitor API key
- `Sentry/{APP_NAME}/dsn`: Sentry DSN for error tracking

#### Step 2: Register Device with Balena Cloud

1. Create a Balena Cloud account at https://www.balena.io/cloud/
2. Create a fleet for your device type (e.g., Raspberry Pi 4)
3. Download the device-specific OS image and flash to SD card
4. Power on device - it will auto-register with your fleet

#### Step 3: Clone Repository

```bash
git clone https://github.com/tailucas/remote-monitor.git
cd remote-monitor
```

#### Step 4: Build and Deploy with Balena CLI

Retrieve your fleet ID:
```bash
balena fleets
```

Push to Balena Cloud (automatically builds and deploys):
```bash
balena push <FLEET_ID>
```

The device will automatically download and start the new image. Monitor progress in the Balena Cloud dashboard.

For local development (requires Docker):

```bash
task build      # Build Docker image locally
task configure  # Generate .env from 1Password secrets
task run        # Run container in foreground
task rund       # Run container detached
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Build System

### Task CLI (Taskfile.yml)

Primary build orchestration:

- `task build` - Build Docker image with all dependencies and application code
- `task run` - Run container in foreground with full log output
- `task rund` - Run container detached (persists after terminal close)
- `task configure` - Generate .env configuration from 1Password secrets
- `task datadir` - Create data directory with proper permissions (UID/GID 999)

### Dockerfile

Custom Debian-based image (not inherited from base-app due to Balena requirements):

- **Base**: `debian:trixie-slim` (not Balena-specific to allow local development)
- **Hardware I2C**: Installs i2c-tools, libzmq3-dev, required for ADC/IOPi boards
- **Locale Support**: Generates locales for en_ZA.UTF-8 (configurable via build args)
- **Tailscale**: Integrated WireGuard VPN client for secure remote access
- **Supervisor**: Process manager for application and cron jobs
- **Python Dependencies**: Installed via uv from pyproject.toml
- **Cron**: Healthchecks heartbeat every 5 minutes, configured via config/cron/
- **User**: Runs as `app` (UID 999) with permissions for i2c, audio, video, dialout
- **Exposed Ports**: 22 (SSH), 5556-5558 (ZeroMQ)

### Dependencies

**Python** (`pyproject.toml`, managed via uv, requires Python 3.11+):
- `abelectronics` - ADC and I/O expander libraries (from git: ABElectronics GitHub)
- `pika>=1.3.2` - RabbitMQ client
- `rpi-gpio>=0.7.1` - Raspberry Pi GPIO interface
- `sentry-sdk>=2.38.0` - Error tracking
- `smbus2>=0.5.0` - I2C SMBus protocol
- `tailucas-pylib>=0.5.6` - Shared utilities (Sentry, 1Password, RabbitMQ, ZeroMQ, threading patterns)

### Configuration

**config/app.conf** (INI format with variable interpolation):
- `[app]`: Device name, tamper label, monitor key
- `[creds]`: Sentry DSN and Cronitor paths
- `[rabbitmq]`: Exchange, topic, server address
- `[adc_address]`: I2C addresses for ADC boards (adc1, adc2)
- `[io_address]`: I2C addresses for I/O expander boards (io1, io2)
- `[relay_address]`: GPIO pin mappings for relays (relay1-relay8)
- `[input_address]`: ADC pin mappings for sensors (I1-I7)
- `[input_location]`, `[input_name]`, `[input_type]`: Metadata for inputs
- `[input_normal_values]`, `[input_tamper_values]`: Thresholds for detection
- `[output_location]`, `[output_type]`: Metadata for relay outputs
- `[output_relay]`: Maps output devices to relay names

**Balena Environment** (Fleet variables):
- Accessed as environment variables at runtime, interpolated into app.conf via config_interpol tool
- Syslog remote address configurable for centralized log aggregation
- Tailscale authkey for automatic VPN connection

**Supervisor Configuration** (config/supervisord.conf):
- Manages two processes: application (uv run app) and cron daemon
- Logs to /data/supervisord.log
- Restarts on unexpected exit

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Application Components

### ADC Sampling & Threshold Detection

The main loop (line 286+) continuously:
1. Reads voltage from all configured ADC inputs (0-5V range)
2. Normalizes to 0-100% scale
3. Compares to configured `input_normal_values` with tolerance window (default ±10%)
4. Tracks state in `device_history` (value, timestamp, detail)
5. Detects tamper conditions against optional `input_tamper_values`
6. Debounces rapid changes to prevent noise

### Message Publishing

**Notify Events** (on state change):
- Topic: `event.notify.{RABBITMQ_DEVICE_TOPIC}.{DEVICE_NAME}`
- Payload includes triggered inputs with sample values and event details

**Heartbeat Events** (every 5 seconds if no activity):
- Topic: `event.heartbeat.{RABBITMQ_DEVICE_TOPIC}.{DEVICE_NAME}`
- Payload includes all input/output device metadata

### Relay Control

**RabbitMQ Control Exchange** (listens on control topic):
- Receives relay trigger commands from other applications
- `ZMQListener` background thread forwards to `RelayControl` via inproc socket
- `Relay.trigger()` activates GPIO pin HIGH, sleeps for duration, returns LOW
- Supports fractional seconds for relay activation timing

### Health Monitoring

**Cron Job** (config/cron/healthchecks_heartbeat):
- Runs every 5 minutes (`*/5 * * * *`)
- Executes healthchecks_heartbeat.sh to ping Healthchecks.io
- Tracks application responsiveness

**Sentry Integration**:
- Async instrumentation enabled
- Thread-safe error capture
- Hardcoded DSN path: `Sentry/{APP_NAME}/dsn` in 1Password

**Cronitor Monitoring**:
- Tracks thread health via tailucas-pylib thread_nanny
- API key stored in 1Password under `Cronitor/password`

## Deployment Patterns

### Balena Cloud Workflow

1. Push to git remote → Balena Cloud receives webhook
2. Builds Dockerfile on Balena builder
3. Generates delta image (only changed layers)
4. Device downloads and applies delta
5. Supervisor restarts application
6. Healthchecks.io and Cronitor report status

### Environment Configuration Flow

1. Device boots with Balena OS
2. Entrypoint runs as root:
   - Loads I2C kernel modules
   - Configures rsyslog (if RSYSLOG_SERVER set)
   - Registers cron jobs from config/cron/
   - Starts Tailscale with TS_AUTHKEY
   - Generates app.conf via config_interpol (variable substitution from env)
   - Changes permissions to app user
3. Supervisor starts application and cron daemon under `app` user
4. Application initializes:
   - Fetches Sentry DSN from 1Password via CredsConfig
   - Connects to RabbitMQ
   - Initializes I2C hardware (ADC/IOPi boards)
   - Starts ZMQ relay control listener
   - Enters main sampling loop

<!-- LICENSE -->
## License

Distributed under the MIT License. See [LICENSE](LICENSE) for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>


<!-- ACKNOWLEDGMENTS -->
## Acknowledgments

* [Template on which this README is based](https://github.com/othneildrew/Best-README-Template)
* [All the Shields](https://github.com/progfay/shields-with-icon)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->
[contributors-shield]: https://img.shields.io/github/contributors/tailucas/remote-monitor.svg?style=for-the-badge
[contributors-url]: https://github.com/tailucas/remote-monitor/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/tailucas/remote-monitor.svg?style=for-the-badge
[forks-url]: https://github.com/tailucas/remote-monitor/network/members
[stars-shield]: https://img.shields.io/github/stars/tailucas/remote-monitor.svg?style=for-the-badge
[stars-url]: https://github.com/tailucas/remote-monitor/stargazers
[issues-shield]: https://img.shields.io/github/issues/tailucas/remote-monitor.svg?style=for-the-badge
[issues-url]: https://github.com/tailucas/remote-monitor/issues
[license-shield]: https://img.shields.io/github/license/tailucas/remote-monitor.svg?style=for-the-badge
[license-url]: https://github.com/tailucas/remote-monitor/blob/master/LICENSE

[blog-url]: https://tailucas.github.io/update/2023/06/11/iot-with-balena-cloud.html

[baseapp-url]: https://github.com/tailucas/base-app
[pylib-url]: https://github.com/tailucas/pylib

[balena-cli-url]: https://docs.balena.io/reference/balena-cli/
[balena-cloud-url]: https://www.balena.io/cloud

[1p-url]: https://developer.1password.com/docs/connect/
[1p-shield]: https://img.shields.io/static/v1?style=for-the-badge&message=1Password&color=0094F5&logo=1Password&logoColor=FFFFFF&label=
[cronitor-url]: https://cronitor.io/
[healthchecks-url]: https://healthchecks.io/
[python-url]: https://www.python.org/
[python-shield]: https://img.shields.io/static/v1?style=for-the-badge&message=Python&color=3776AB&logo=Python&logoColor=FFFFFF&label=
[rabbit-url]: https://www.rabbitmq.com/
[rabbit-shield]: https://img.shields.io/static/v1?style=for-the-badge&message=RabbitMQ&color=FF6600&logo=RabbitMQ&logoColor=FFFFFF&label=
[rpi-shield]: https://img.shields.io/static/v1?style=for-the-badge&message=Raspberry+Pi&color=A22846&logo=Raspberry+Pi&logoColor=FFFFFF&label=
[rpi-url]: https://www.raspberrypi.org/
[sentry-url]: https://sentry.io/
[sentry-shield]: https://img.shields.io/static/v1?style=for-the-badge&message=Sentry&color=362D59&logo=Sentry&logoColor=FFFFFF&label=
[tailscale-url]: https://tailscale.com/
[zmq-url]: https://zeromq.org/
[zmq-shield]: https://img.shields.io/static/v1?style=for-the-badge&message=ZeroMQ&color=DF0000&logo=ZeroMQ&logoColor=FFFFFF&label=
[abelectronics-url]: https://github.com/abelectronicsuk/ABElectronics_Python_Libraries
