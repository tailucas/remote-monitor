#!/usr/bin/env bash
set -e
set -o pipefail

pyvenv /opt/app/
. /opt/app/bin/activate
# work around wheel stupidity
pip3 install wheel
pip3 install -r "/opt/app/config/requirements.txt"
pip3 install git+https://github.com/abelectronicsuk/ABElectronics_Python_Libraries.git
deactivate
