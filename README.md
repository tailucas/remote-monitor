# remote_monitor

Python application to GPIO sample boards made by https://www.abelectronics.co.uk/. In particular, the ADC board and IO Board.

## Notes for Balena Cloud

This project is structured as is for use with [Balena Cloud](https://www.balena.io/cloud/) and requires the *service variables* listed below to be set in order for the application to start properly. It is best to configure these at the level of the Balena application as opposed to the device because all device variables are local to each device.

Since this project uses additional remotes for [Git submodule](https://git-scm.com/book/en/v2/Git-Tools-Submodules) usage, a *push* to the Balena remote is insufficient to include all artifacts for the build. For this, you need to use the *balena push* command supplied by the [balena CLI](https://github.com/balena-io/balena-cli). Be sure to use the correct Balena application name when using *balena push* because the tool will not perform validation of the local context against the build deployed to the device.

```text
API_KEY_RESIN
APP_NAME
APP_ZMQ_PUBSUB_PORT
APP_ZMQ_PUSHPULL_PORT
AWS_ACCESS_KEY_ID
AWS_CONFIG_FILE
AWS_DEFAULT_REGION
AWS_SECRET_ACCESS_KEY
AWS_SHARED_CREDENTIALS_FILE
FIELD_A1_LABEL
FIELD_A2_LABEL
FIELD_A3_LABEL
FIELD_A4_LABEL
HOUSE_ALARM_ZONE_1
HOUSE_ALARM_ZONE_2
HOUSE_ALARM_ZONE_3
HOUSE_ALARM_ZONE_4
HOUSE_ALARM_ZONE_5
HOUSE_ALARM_ZONE_6
INPUT_1_LOCATION
INPUT_1_NAME
INPUT_1_TYPE
INPUT_1_VALUE_NORMAL
INPUT_1_VALUE_TAMPER
INPUT_2_LOCATION
INPUT_2_NAME
INPUT_2_TYPE
INPUT_2_VALUE_NORMAL
INPUT_2_VALUE_TAMPER
INPUT_3_LOCATION
INPUT_3_NAME
INPUT_3_TYPE
INPUT_3_VALUE_NORMAL
INPUT_3_VALUE_TAMPER
INPUT_4_LOCATION
INPUT_4_NAME
INPUT_4_TYPE
INPUT_4_VALUE_NORMAL
INPUT_4_VALUE_TAMPER
INPUT_5_LOCATION
INPUT_5_NAME
INPUT_5_TYPE
INPUT_5_VALUE_NORMAL
INPUT_6_LOCATION
INPUT_6_NAME
INPUT_6_TYPE
INPUT_6_VALUE_NORMAL
INPUT_7_LOCATION
INPUT_7_NAME
INPUT_7_TYPE
INPUT_7_VALUE_NORMAL
INPUT_7_VALUE_TAMPER
INPUT_NORMAL_VALUE
INPUT_TAMPER_LABEL
INPUT_TAMPER_VALUE
OUTPUT_1_LOCATION
OUTPUT_1_RELAY
OUTPUT_1_TYPE
OUTPUT_2_LOCATION
OUTPUT_2_RELAY
OUTPUT_2_TYPE
OUTPUT_3_LOCATION
OUTPUT_3_RELAY
OUTPUT_3_TYPE
OUTPUT_4_LOCATION
OUTPUT_4_RELAY
OUTPUT_4_TYPE
REMOVE_KERNEL_MODULES
RSYSLOG_LOGENTRIES_SERVER
RSYSLOG_LOGENTRIES_TOKEN
RSYSLOG_SERVER
SENTRY_DSN
SERIAL_BAUD
SERIAL_PORT
SSH_AUTHORIZED_KEY
```
