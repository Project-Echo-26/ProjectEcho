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
export VENV_PATH="$HOME/ProjectEcho/.venv"
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
- DO NOT use this one, unless you are building for the physical board
```Shell
./waf configure --board speedybeef4v4
```
- Use this one for simulation
```shell
./waf configure --board sitl
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

## Gazebo Setup
### Install Gazebo Binary
- Prerequisite Tools
```shell
sudo apt-get update
sudo apt-get install curl lsb-release gnupg
```
- Install Gazebo Harmonic
```shell
sudo curl https://packages.osrfoundation.org/gazebo.gpg --output /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] https://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/gazebo-stable.list > /dev/null
sudo apt-get update
sudo apt-get install gz-harmonic
```
### Setup Gazebo Submodule for Ardupilot
- Install additional dependencies
```shell
sudo apt update
sudo apt install libgz-sim8-dev rapidjson-dev
sudo apt install libopencv-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl
```
- Build ardupilot_gazebo submodule
```shell
cd ardupilot_gazebo
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo
make -j4
```
- Configure Gazebo environment variables
```shell
echo 'export GZ_SIM_SYSTEM_PLUGIN_PATH=$HOME/ProjectEcho/ardupilot_gazebo/build:${GZ_SIM_SYSTEM_PLUGIN_PATH}' >> ~/.bashrc
echo 'export GZ_SIM_RESOURCE_PATH=$HOME/ProjectEcho/ardupilot_gazebo/models:$HOME/ProjectEcho/ardupilot_gazebo/worlds:${GZ_SIM_RESOURCE_PATH}' >> ~/.bashrc
source ~/.bashrc
```

## Credits
- [Gavin Ebel](https://github.com/Gav0822)
- [Justin Puterbaugh]
- [Trinity Woods]
- [Ulrich Batanado]
- [Bryan Agamu]
- All associated with the [ArduPilot Project](https://github.com/ardupilot/ardupilot)
