<a name="readme-top"></a>

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]

## About The Project

**Note 1**: See my write-up on [IoT with Balena Cloud][blog-url]. Here you can find a brief write-up about my projects based on Balena Cloud and my general experience with this IoT platform.

**Note 2**: If you are already familiar with my [Base Application][baseapp-url], you will notice a similar structure here but since this application is [rooted in Balena images](https://github.com/tailucas/remote-monitor/blob/1201986ef3ba2e366c3ced5c1ece879a5379163a/Dockerfile#L1), it needs to carry a few of its own functions like the supervisor configuration. Although this project carries some duplication of functionality factored out from my other projects, the relative simplicity of this project to support Balena provides some justification.

This is a Python project designed specifically to interface with the [Raspberry Pi][rpi-url] GPIO [interface](https://projects.raspberrypi.org/en/projects/physical-computing/1) with both an attached analog-to-digital converter (ADC) and I/O expander board to which output signals are sent. The purpose of this configuration is to be able to sense inputs on the ADC, process these inputs elsewhere and then support sending output signals on the I/O channels. The blog post above provides context behind this setup. The other feature of this project is that it is configured for deployment to the device via Balena Cloud, a web service that makes it easy to link git actions to deployment actions.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Built With

Technologies that help make this project useful:

[![1Password][1p-shield]][1p-url]
[![RabbitMQ][rabbit-shield]][rabbit-url]
[![Raspberry Pi][rpi-shield]][rpi-url]
[![Poetry][poetry-shield]][poetry-url]
[![Python][python-shield]][python-url]
[![Sentry][sentry-shield]][sentry-url]
[![ZeroMQ][zmq-shield]][zmq-url]

Also:

* [Balena Cloud][balena-cloud-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>


<!-- GETTING STARTED -->
## Getting Started

Here is some detail about the intended use of this package.

### Prerequisites

Beyond the Python dependencies defined in the [Poetry configuration](pyproject.toml), the package init carries hardcoded dependencies on [Sentry][sentry-url] and [1Password][1p-url] in order to function in order to function. Unless you want these you're likely better off forking this package and cutting out what you do not need.

This project is structured as is for use with [Balena Cloud](https://www.balena.io/cloud/) and requires the Fleet *service variables* listed below to be set in order for the application to start properly.

:bulb: It is best to configure these at the level of the Balena Fleet as opposed to the device because all device variables are local to each device and are deleted with the device when you decommission broken devices.

Since this project uses additional remotes for [Git submodule](https://git-scm.com/book/en/v2/Git-Tools-Submodules) usage, a *push* to the Balena remote is insufficient to include all artifacts for the build. For this, you need to use the *balena push* command supplied by the [balena CLI](https://github.com/balena-io/balena-cli). Be sure to use the correct Balena application name when using *balena push* because the tool will not perform validation of the local context against the build deployed to the device and so you could run the risk of deploying the wrong code to a fleet.

Assuming that you have [registered your device](https://docs.balena.io/learn/getting-started) with Balena Cloud, the [Balena CLI][balena-cli-url] tool is then used to push your project to the Balena builder. To do this, fetch either the fleet or device ID using either `balena fleets` or `balena devices`. Then use `balena push` to push the project including the git-submodule to the builder. If successful, the device will automatically begin downloading the image delta generated for the new release revision.

#### Basic Functions

This project showcases a variety of common functionality borrowed from one of my [common libraries][pylib-url] and so is relatively compact for what it does.
* A 1Password [CredsConfig](https://github.com/tailucas/remote-monitor/blob/1201986ef3ba2e366c3ced5c1ece879a5379163a/app/__main__.py#L25-L27) instance is created to support Sentry and Cronitor monitoring (for thread death).
* `pylib.rabbit` has plenty of exception handling and so some Rabbit loggers [need to be ignored](https://github.com/tailucas/remote-monitor/blob/1201986ef3ba2e366c3ced5c1ece879a5379163a/app/__main__.py#L46-L51) in order to avoid needless Sentry tickets for issues typically triggered by network conditions. Of course, there's always a risk of masking other unchecked issues so use this sparingly.
* This project uses [ZeroMQ][zmq-url] for inter-thread IPC for which [these](https://github.com/tailucas/remote-monitor/blob/1201986ef3ba2e366c3ced5c1ece879a5379163a/app/__main__.py#L60-L61) *inproc* URLs are defined.
* [Relay](https://github.com/tailucas/remote-monitor/blob/1201986ef3ba2e366c3ced5c1ece879a5379163a/app/__main__.py#L64-L94) abstracts a physical electronic relay. Upon receipt of a message, will send an output signal on the associated address.
* [RelayControl](https://github.com/tailucas/remote-monitor/blob/1201986ef3ba2e366c3ced5c1ece879a5379163a/app/__main__.py#L97-L141) is aware of how many relays are configured on the shield outputs and addresses them by label.
* The [main application loop](https://github.com/tailucas/remote-monitor/blob/1201986ef3ba2e366c3ced5c1ece879a5379163a/app/__main__.py#L279-L358) is responsible for sampling from the ADC inputs, translating and applying thresholds the sampled input values, determining outlier values and then ultimately dispatching a message to the RabbitMQ bus for further processing.

### Installation

:stop_sign: This project uses [1Password Secrets Automation][1p-url] to store both application key-value pairs as well as runtime secrets. It is assumed that the connect server containers are already running on your environment. If you do not want to use this, then you'll need to fork this package and make the changes as appropriate. It's actually very easy to set up, but note that 1Password is a paid product with a free-tier for secrets automation. An example of the items fetched from 1Password can be found [here](https://github.com/tailucas/remote-monitor/blob/1201986ef3ba2e366c3ced5c1ece879a5379163a/app/__main__.py#L25-L27).

Here is the list of Balena Fleet variables used by this application:

* `APP_NAME`: Used for referencing the application's actual name for the logger. This project uses `remote_monitor`.
* `AWS_CONFIG_FILE`: Standard local location of the AWS configuration file. This project uses `/home/app/.aws/config`. Used previously for some AWS SWF integration but is required for build until I trim this out.
* `AWS_DEFAULT_REGION`: As above used previously. Set to anything valid like `us-east-1`.
* `CRONITOR_MONITOR_KEY`: Token to enable additional health checks presented in [Cronitor][cronitor-url]. This tracks thread count and overall health.
* `OP_CONNECT_SERVER`, `OP_CONNECT_TOKEN`, `OP_CONNECT_VAULT`: Used to specify the URL of the 1Password connect server with associated client token and Vault ID. See [1Password](https://developer.1password.com/docs/connect/get-started#step-1-set-up-a-secrets-automation-workflow) for more.
* `HC_PING_URL`: [Healthchecks][healthchecks-url] URL of this application's current health check status.
* `INPUT_*`, `OUTPUT_*`: Used as label substitutions in the [application configuration](https://github.com/tailucas/remote-monitor/blob/1201986ef3ba2e366c3ced5c1ece879a5379163a/config/app.conf#L39-L98).
* `RABBITMQ_DEVICE_TOPIC`: Input and output messages to another application for decision making. This project uses `ioboard`.
* `RABBITMQ_EXCHANGE`: RabbitMQ has a configured exchange on which topics are registered. This project uses `home_automation`.
* `RABBITMQ_SERVER_ADDRESS`: IP address of the RabbitMQ server.
* `RSYSLOG_SERVER`: IP address of the desired rsyslog server.

With these configured, you are now able to build the application.

1. Clone the repo
   ```sh
   git clone https://github.com/tailucas/remote-monitor.git
   cd remote-monitor
   ```
2. Verify that the git submodule is present.
   ```sh
   git submodule init
   git submodule update
   ```
4. Retrieve the Balena Fleet or Device ID using the Balena CLI.
   ```sh
   balena fleets
   balena devices
   ```
3. Push to Balena Cloud which triggers a build and automatic device download.
   ```sh
   balena push $FLEET_ID
   ```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- USAGE EXAMPLES -->
## Usage

If your device is properly registered with Balena Cloud by downloading your device-specific operating system image, it should be visible in the management interface. Thereafter a successful build of your project via `balena push` should be enough to download and start your application.

<p align="right">(<a href="#readme-top">back to top</a>)</p>


<!-- LICENSE -->
## License

Distributed under the MIT License. See [LICENSE](LICENSE) for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>


<!-- ACKNOWLEDGMENTS -->
## Acknowledgments

* [Template on which this README is based](https://github.com/othneildrew/Best-README-Template)
* [All the Shields](https://github.com/progfay/shields-with-icon)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

[![Hits](https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fgithub.com%2Ftailucas%2Fremote-monitor&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=visits&edge_flat=true)](https://hits.seeyoufarm.com)

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
[poetry-url]: https://python-poetry.org/
[poetry-shield]: https://img.shields.io/static/v1?style=for-the-badge&message=Poetry&color=60A5FA&logo=Poetry&logoColor=FFFFFF&label=
[python-url]: https://www.python.org/
[python-shield]: https://img.shields.io/static/v1?style=for-the-badge&message=Python&color=3776AB&logo=Python&logoColor=FFFFFF&label=
[rabbit-url]: https://www.rabbitmq.com/
[rabbit-shield]: https://img.shields.io/static/v1?style=for-the-badge&message=RabbitMQ&color=FF6600&logo=RabbitMQ&logoColor=FFFFFF&label=
[rpi-shield]: https://img.shields.io/static/v1?style=for-the-badge&message=Raspberry+Pi&color=A22846&logo=Raspberry+Pi&logoColor=FFFFFF&label=
[rpi-url]: https://www.raspberrypi.org/
[sentry-url]: https://sentry.io/
[sentry-shield]: https://img.shields.io/static/v1?style=for-the-badge&message=Sentry&color=362D59&logo=Sentry&logoColor=FFFFFF&label=
[zmq-url]: https://zeromq.org/
[zmq-shield]: https://img.shields.io/static/v1?style=for-the-badge&message=ZeroMQ&color=DF0000&logo=ZeroMQ&logoColor=FFFFFF&label=
