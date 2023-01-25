#!/usr/bin/env sh
set -e
set -o pipefail

# virtual-env updates
python -m venv /opt/app/
. /opt/app/bin/activate
python -m site
# work around timeouts to www.piwheels.org
export PIP_DEFAULT_TIMEOUT=60

python -m pip install --upgrade pip
python -m pip install --upgrade setuptools
python -m pip install --upgrade wheel

python -m pip install --upgrade -r "/opt/app/requirements.txt"
# add pylib dependencies
if [ -f /opt/app/pylib/requirements.txt ]; then
  python -m pip install --upgrade -r "/opt/app/pylib/requirements.txt"
fi
python -m pip install git+https://github.com/abelectronicsuk/ABElectronics_Python_Libraries.git

deactivate
