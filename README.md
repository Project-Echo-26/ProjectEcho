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

### Automated two-drone mesh launcher

After building the SITL binary and the `ardupilot_gazebo` plugin as described
above, start the complete simulation with:

```bash
cd ~/ProjectEcho
bash telemetry_poc/run_two_drones.sh
```

The script launches the two-drone Gazebo world, two SITL instances, the mesh
router, and one peer telemetry receiver per drone. It keeps logs and SITL state
under `~/.local/state/projectecho/two-drone-mesh/` (or
`$XDG_STATE_HOME/projectecho/two-drone-mesh/`) and stops the processes it
started when you press Ctrl+C.

The launcher runs MAVProxy in the background rather than opening separate
MAVProxy consoles. It sends both vehicles' telemetry to Mission Planner on
UDP port `14550`, using the WSL default gateway as the Windows host address.
If that address is not detected correctly, set `WINDOWS_HOST_IP` before
launching. Peer mesh telemetry is printed in the
`receiver-drone-1.log` and `receiver-drone-2.log` files in the state directory.
The mesh settings can be overridden with `MESH_RANGE_M`, `MESH_BANDWIDTH`,
`MESH_LATENCY_MS`, `MESH_PACKET_LOSS`, and `MESH_MAX_HOPS`.

#### Control the SITL vehicles

The launcher keeps MAVProxy in the background, so it does not open interactive
MAVProxy terminals. To control the vehicles, open Mission Planner on Windows,
select the **UDP** connection, and connect on port `14550`. Both SITL instances
send telemetry through that connection with system IDs 1 and 2. Use Mission
Planner's vehicle selection and Flight Data controls to choose a vehicle and
send commands. The mesh router is telemetry-only; control commands use the
direct MAVProxy-to-GCS connection.

If arming is rejected with `PreArm: Motors: Check frame class and type`, set
`FRAME_CLASS` and `FRAME_TYPE` to `1` for each vehicle in Mission Planner's
parameter list, write the parameters, and reboot that SITL instance. Only
control these simulated vehicles.

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

## Local Telemetry Receiver Test (SITL)

This test checks that telemetry from both SITL drones can be received, identified by system ID, and updated when one drone changes altitude. The commands below use the project paths from this README.

### Start the Two-Drone Simulation

- In the Gazebo terminal

```bash
cd ~/ProjectEcho/ardupilot_gazebo/worlds
gz sim -v4 -r iris_two_basic.sdf
```

- In Drone 1's terminal, start SITL

```bash
cd ~/ProjectEcho
./Tools/autotest/sim_vehicle.py -v ArduCopter -f gazebo-iris --model JSON -I0 --sysid 1 --use-dir copter0 --map --console
```

- In Drone 2's terminal, start the second SITL instance

```bash
cd ~/ProjectEcho
./Tools/autotest/sim_vehicle.py -v ArduCopter -f gazebo-iris --model JSON -I1 --sysid 2 --use-dir copter1
```

- Wait for both SITL instances to connect

### Start the Telemetry Receivers

- The receiver script is `~/ProjectEcho/telemetry_poc/receiver.py`
- Confirm that `pymavlink` is available to Python

```bash
python3 -c "from pymavlink import mavutil; print('pymavlink is available')"
```

- Open two additional WSL terminals and start one receiver in each

```bash
cd ~/ProjectEcho/telemetry_poc
python3 receiver.py --port 14600
```

```bash
cd ~/ProjectEcho/telemetry_poc
python3 receiver.py --port 14601
```

### Forward Telemetry to the Receivers

- In Drone 1's MAVProxy terminal, check the current outputs

```text
output
```

- Keep the normal output and add the shared receiver if it is not already listed

```text
output add 127.0.0.1:14600
```

- In Drone 2's MAVProxy terminal, check the current outputs

```text
output
```

- Keep the normal output and add both receiver ports if they are not already listed

```text
output add 127.0.0.1:14600
output add 127.0.0.1:14601
```

- Check `output` in each MAVProxy terminal to confirm the test destinations are listed only once
- Do not remove the normal MAVProxy outputs

### Verify and Test Telemetry

- The receiver on port `14600` should display messages from System 1 and System 2
- The receiver on port `14601` should display messages from System 2
- Messages include heartbeat and position data, with the system ID shown in the receiver output

#### Test Route Recovery

- In Drone 2's MAVProxy terminal, temporarily remove its route to the shared receiver

```text
output remove 127.0.0.1:14600
```

- Port `14600` should show System 1 only; port `14601` should continue showing System 2
- Restore the route

```text
output add 127.0.0.1:14600
```

- Port `14600` should show both system IDs again

#### Test Changing Altitude

- In Drone 2's MAVProxy terminal, enter these commands one at a time

```text
mode guided
arm throttle
takeoff 3
```

- Watch port `14600`: System 2's `relative_alt` should rise to about 3 m, while System 1 remains near 0 m
- Land Drone 2

```text
land
```

- Confirm System 2's `relative_alt` returns to about 0 m

**Troubleshooting:** During the first altitude check, port `14601` showed the altitude change while the combined receiver on port `14600` continued showing 0 m for System 2. Restarting the receiver on port `14600` resolved the display mismatch. If this happens, check Drone 2's `output` list, then restart only the receiver on port `14600` while Drone 2 is still sending telemetry.

### Test Results and Limitations

- Port `14600` received and identified telemetry from both system IDs
- Port `14601` received System 2 telemetry
- Removing Drone 2's route to port `14600` removed System 2 from that receiver; restoring the route brought it back
- During a simulated takeoff to 3 m and landing, the shared receiver showed System 2's altitude rise to about 3 m and return to about 0 m, while System 1 remained near 0 m
- This test used local UDP forwarding through `127.0.0.1`. Each SITL instance sent telemetry directly to the receiver; neither drone relayed the other drone's messages. This test does not demonstrate a wireless mesh network, communication range, packet loss, or latency.

### Simulated Mesh Telemetry

`telemetry_poc/mesh_router.py` simulates a local, position-aware telemetry mesh.
It reads MAVLink telemetry sent by each drone's MAVProxy instance, forms links
between nodes whose latest reported positions are within radio range, and
forwards `HEARTBEAT` and `GLOBAL_POSITION_INT` messages to reachable peer
receivers. Relaying is store-and-forward with a configurable hop limit. Each
hop applies bandwidth serialization, latency, and seeded packet loss.

This is a configurable network approximation, not a radio propagation or
obstacle model. It uses the drones' MAVLink-reported positions and only forwards
the two telemetry message types shown by the receiver above; it does not forward
arming, mode-change, or other command messages into either flight controller.
The router is a centralized local emulator: SITL sends telemetry to it over
loopback, and its per-node output port is a peer-consumer socket (the
`receiver.py` instance below), not an ArduPilot input. A companion process can
consume telemetry from that socket if needed.

#### Start the mesh router and peer receivers

- Start the two-drone Gazebo and SITL setup described above.
- Open a terminal for the mesh router:

```bash
cd ~/ProjectEcho/telemetry_poc
python3 mesh_router.py \
  --node 1:14610:14620 \
  --node 2:14611:14621 \
  --range-m 100 \
  --bandwidth 57600 \
  --latency-ms 20 \
  --packet-loss 0.01 \
  --max-hops 4
```

Each `--node` value is `SYSTEM_ID:MAVPROXY_INPUT_PORT:PEER_RECEIVER_PORT`.
The ports must be unique. For this example, Drone 1's telemetry enters the
router on port `14610` and peer telemetry for Drone 1 is delivered to port
`14620`; Drone 2 uses ports `14611` and `14621`.

- In Drone 1's MAVProxy terminal, add the router input:

```text
output add 127.0.0.1:14610
```

- In Drone 2's MAVProxy terminal, add its router input:

```text
output add 127.0.0.1:14611
```

- Start one peer receiver for each drone:

```bash
cd ~/ProjectEcho/telemetry_poc
python3 receiver.py --port 14620
```

```bash
cd ~/ProjectEcho/telemetry_poc
python3 receiver.py --port 14621
```

With the drones within range and both position reports fresh, each receiver
should show telemetry from the other drone. Lower `--range-m` below their
reported separation to break the link; raise it to restore the link. To test
loss and delay, adjust `--packet-loss` and `--latency-ms`. The random loss
sequence is repeatable with the same `--seed` and same packet ordering. A node
whose last position is older than `--position-timeout` seconds is excluded from
the mesh. When adding more drones, give each a unique system ID and pair of
unused ports with another `--node` option.

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

- Add and test a third simulated drone to demonstrate multi-hop relay
- Add terrain/obstacle-aware propagation and configurable radio link profiles
  
## Credits
- [Gavin Ebel](https://github.com/Gav0822)
- [Justin Puterbaugh](https://github.com/Jputerbaugh)
- [Trinity Woods]
- [Ulrich Batanado]
- [Bryan Agamu]
- All associated with the [ArduPilot Project](https://github.com/ardupilot/ardupilot)
