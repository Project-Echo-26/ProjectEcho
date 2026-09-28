# Project Echo

## Setup

### WSL / Ubuntu
Documentation found [here](https://ardupilot.org/dev/docs/building-setup-linux.html)

- Install prerequisite packages
```Shell
sudo apt-get update
sudo apt-get install git gitk git-gui
```
- Clone this repository
```Shell
git clone --recurse-submodules https://github.com/Project-Echo-26/ProjectEcho.git
cd ProjectEcho
```
- **IMPORTANT**: Set VENV_PATH environment variable!
```Shell
export VENV_PATH="~/ProjectEcho/.venv"
```
- Install required packages
```
./Tools/environment_install/install-prereqs-ubuntu.sh -y
```
- Reload PATH
```Shell
source ~/.profile
```

## Build Flight Controller Code
Echo Project choice flight controller hardware: [SpeedyBeeF405V4](https://www.speedybee.com/speedybee-f405-v4-bls-55a-30x30-fc-esc-stack/)
### To Build
```Shell
./waf configure --board speedybeef4v4
./waf copter
```
### To Clean
```shell
./waf clean
```

## Run Simulation
```Shell
./Tools/autotest/sim_vehicle.py
```

## Credits
- [Gavin Ebel](https://github.com/Gav0822)
- [Justin Puterbaugh]
- [Trinity Woods]
- [Ulrich Batanado]
- [Bryan Agamu]
- All associated with the [ArduPilot Project](https://github.com/ardupilot/ardupilot)
