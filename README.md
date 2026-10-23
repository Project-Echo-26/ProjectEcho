# Project Echo

## Setup

### WSL / Ubuntu

Documentation found [here](https://ardupilot.org/dev/docs/building-setup-linux.html)

- Install prerequisite packages

```bash
sudo apt-get update
sudo apt-get install git gitk git-gui
```

- Clone this repository

```bash
git clone --recurse-submodules https://github.com/Project-Echo-26/ProjectEcho.git
cd ProjectEcho
```

- **IMPORTANT:** Set VENV_PATH environment variable!

```bash
export VENV_PATH="$HOME/ProjectEcho/.venv"
```

- Install required packages

```bash
./Tools/environment_install/install-prereqs-ubuntu.sh -y
```

- Reload PATH

```bash
source ~/.profile
```

## Build Flight Controller Code

Echo Project choice flight controller hardware: [SpeedyBeeF405V4](https://www.speedybee.com/speedybee-f405-v4-bls-55a-30x30-fc-esc-stack/)

### To Build

- DO NOT use this one unless building for the physical board

```bash
./waf configure --board speedybeef4v4
```

- Use this one for simulation

```bash
./waf configure --board sitl
./waf copter
```

### To Clean

```bash
./waf clean
```

## Run Simulation

```bash
./Tools/autotest/sim_vehicle.py
```

## Gazebo Setup

### Install Gazebo Binary

- Prerequisite tools

```bash
sudo apt-get update
sudo apt-get install curl lsb-release gnupg
```

- Install Gazebo Harmonic

```bash
sudo curl https://packages.osrfoundation.org/gazebo.gpg --output /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
```

```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] https://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/gazebo-stable.list > /dev/null
```

```bash
sudo apt-get update
sudo apt-get install gz-harmonic
```

### Setup Gazebo Submodule for Ardupilot

- Install additional dependencies

```bash
sudo apt update
sudo apt install libgz-sim8-dev rapidjson-dev
sudo apt install libopencv-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl
```

- Build ardupilot_gazebo submodule

```bash
cd ~/ProjectEcho/ardupilot_gazebo
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo
make -j4
```

- Configure Gazebo environment variables

```bash
echo 'export GZ_SIM_SYSTEM_PLUGIN_PATH=$HOME/ProjectEcho/ardupilot_gazebo/build:${GZ_SIM_SYSTEM_PLUGIN_PATH}' >> ~/.bashrc
echo 'export GZ_SIM_RESOURCE_PATH=$HOME/ProjectEcho/ardupilot_gazebo/models:$HOME/ProjectEcho/ardupilot_gazebo/worlds:${GZ_SIM_RESOURCE_PATH}' >> ~/.bashrc
source ~/.bashrc
```

## Run Gazebo with SITL

- Open Ubuntu Terminal 1 and start Gazebo

```bash
gz sim -v4 -r iris_runway.sdf
```

- Open Ubuntu Terminal 2 and start SITL

```bash
cd ~/ProjectEcho
./Tools/autotest/sim_vehicle.py -v ArduCopter -f gazebo-iris --model JSON --map --console
```

- Wait for MAVProxy to connect

- In the MAVProxy terminal, enter the following commands one at a time

```text
mode guided
arm throttle
takeoff 5
```

- To land the drone

```text
mode land
```

## Multiple Drone Setup

The following steps allow multiple drones to run in the same Gazebo simulation using separate SITL instances.

### Verify Basic Iris Model

- The basic Iris model (`iris_with_ardupilot`) is included with the ArduPilot Gazebo plugin

- Navigate to the Gazebo models directory

```bash
cd ~/ProjectEcho/ardupilot_gazebo/models
```

- Check that the basic Iris model exists

```bash
ls iris_with_ardupilot
```

- Verify that the model includes the ArduPilot plugin

```bash
grep -n 'ArduPilotPlugin' iris_with_ardupilot/model.sdf
```

- The original model uses FDM port 9002 and does not need to be modified

- We will use this model for Drone 1 and create a copy for Drone 2

**Note:** Use `iris_with_ardupilot` instead of `iris_with_gimbal`. The gimbal models caused significant performance issues when running multiple drones.

### Create Second Drone Model

- Navigate to the Gazebo models directory

```bash
cd ~/ProjectEcho/ardupilot_gazebo/models
```

- Copy the existing Iris model

```bash
cp -r iris_with_ardupilot iris_with_ardupilot_2
```

- Open the new model

```bash
nano iris_with_ardupilot_2/model.sdf
```

- Change the model name to

```xml
<model name="iris_with_ardupilot_2">
```

- Change the FDM port from 9002 to 9012

```xml
<fdm_port_in>9012</fdm_port_in>
```

- Save and exit

- Open the model configuration

```bash
nano iris_with_ardupilot_2/model.config
```

- Change the model name to

```xml
<name>iris_with_ardupilot_2</name>
```

### Create Two-Drone Gazebo World

- Navigate to the worlds directory

```bash
cd ~/ProjectEcho/ardupilot_gazebo/worlds
```

- Copy the original world file

```bash
cp iris_runway.sdf iris_two_basic.sdf
```

- Open the new world file

```bash
nano iris_two_basic.sdf
```

- Find the original drone include section and replace it with

```xml
<include>
  <name>drone_1</name>
  <uri>model://iris_with_ardupilot</uri>
  <pose degrees="true">0 0 0.195 0 0 90</pose>
</include>

<include>
  <name>drone_2</name>
  <uri>model://iris_with_ardupilot_2</uri>
  <pose degrees="true">3 0 0.195 0 0 90</pose>
</include>
```

- Save and exit

This places the drones 3 meters apart.

## Run Multiple Drones

### Terminal 1 — Gazebo

- Open Ubuntu and start the two-drone world

```bash
cd ~/ProjectEcho/ardupilot_gazebo/worlds
gz sim -v4 -r iris_two_basic.sdf
```

### Terminal 2 — Drone 1

- Open another Ubuntu terminal

```bash
cd ~/ProjectEcho
./Tools/autotest/sim_vehicle.py -v ArduCopter -f gazebo-iris --model JSON -I0 --sysid 1 --use-dir copter0 --map --console
```

### Terminal 3 — Drone 2

- Open another Ubuntu terminal

```bash
cd ~/ProjectEcho
./Tools/autotest/sim_vehicle.py -v ArduCopter -f gazebo-iris --model JSON -I1 --sysid 2 --use-dir copter1
```

- Wait for both SITL instances to connect

- Check the connection in each MAVProxy terminal

```text
link
```

Both should report `link 1 OK`.

### Drone Configuration

- Check the frame settings in each MAVProxy terminal

```text
param show FRAME_CLASS
param show FRAME_TYPE
```

- Both should be set to 1

- If needed, change them using

```text
param set FRAME_CLASS 1
param set FRAME_TYPE 1
```

- Reboot the SITL instance if required

- Allow time for the sensors to initialize before arming

### Test Independent Flight

- In Drone 1's MAVProxy terminal

```text
mode guided
arm throttle
takeoff 5
```

- Verify only Drone 1 takes off

- Land Drone 1

```text
mode land
```

- Repeat using Drone 2's MAVProxy terminal

## Mission Planner Setup

Mission Planner runs on Windows and connects to both SITL instances through UDP.

### Configure Telemetry

- Find the Windows host IP from Ubuntu

```bash
ip route | grep default
```

- Example output

```text
default via 172.27.240.1 dev eth0
```

The IP may be different depending on the computer or WSL session.

- In Drone 1's MAVProxy terminal, check the existing output

```text
output
```

- If needed, add the Windows IP with port 14550

```text
output add WINDOWS_IP:14550
```

- Repeat for Drone 2

```text
output add WINDOWS_IP:14550
```

Replace `WINDOWS_IP` with the address from the previous step. Do not add a duplicate output if the correct address and port are already listed.

### Connect Mission Planner

- Open Mission Planner on Windows
- Select UDP in the upper-right connection dropdown
- Click CONNECT
- Enter port 14550 if prompted
- Both drones should appear on the map
- Use the vehicle dropdown to switch between Drone 1 and Drone 2

### Control Drone Through Mission Planner

- Select the drone using the vehicle dropdown
- Open the Actions tab
- Change the flight mode to GUIDED
- Arm the selected drone
- Right-click the map and select TakeOff
- Enter 5 meters for the altitude
- Verify the selected drone takes off
- Change the flight mode to LAND when finished
- Repeat for the second drone if needed

Make sure the correct drone is selected before sending commands.

## Simulation Performance

We had performance issues when using multiple drones with gimbals. Switching to the basic Iris models significantly improved simulation speed.

### Check Performance

- Open another Ubuntu terminal

```bash
gz topic -l | grep stats
```

- Check the simulation statistics

```bash
gz topic -e -t /world/iris_runway/stats
```

- Look for `real_time_factor`

A value near 1.0 indicates the simulation is running close to real time.

## Shut Down Simulation

- Land and disarm both drones
- Disconnect Mission Planner
- Enter `exit` in each MAVProxy terminal
- Stop any remaining SITL processes with `Ctrl + C`
- Close Gazebo

## Future Work

- Add a third simulated drone
- Simulate communication between drones
- Simulate communication range and connection loss
- Implement mesh networking between drones
  
## Credits
- [Gavin Ebel](https://github.com/Gav0822)
- [Justin Puterbaugh] (https://github.com/Jputerbaugh)
- [Trinity Woods]
- [Ulrich Batanado]
- [Bryan Agamu]
- All associated with the [ArduPilot Project](https://github.com/ardupilot/ardupilot)
