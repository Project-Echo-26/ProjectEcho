## Listens on the requested UDP port and prints heartbeat and position messages, labeled by the sender’s system ID:

import argparse

from pymavlink import mavutil


def main():
    parser = argparse.ArgumentParser(
        description="Receive and print MAVLink telemetry over UDP."
    )
    parser.add_argument(
        "--port",
        type=int,
        default=14600,
        help="UDP port to listen on (default: 14600)",
    )
    args = parser.parse_args()

    connection = mavutil.mavlink_connection(
        f"udpin:0.0.0.0:{args.port}"
    )

    print(f"Listening for MAVLink telemetry on UDP port {args.port}...")

    try:
        while True:
            message = connection.recv_match(
                type=["HEARTBEAT", "GLOBAL_POSITION_INT"],
                blocking=True,
                timeout=1,
            )

            if message is None:
                continue

            system_id = message.get_srcSystem()
            message_type = message.get_type()

            if message_type == "HEARTBEAT":
                print(f"[System {system_id}] HEARTBEAT received", flush=True)

            elif message_type == "GLOBAL_POSITION_INT":
                latitude = message.lat / 1e7
                longitude = message.lon / 1e7
                relative_altitude = message.relative_alt / 1000

                print(
                    f"[System {system_id}] Position: "
                    f"lat={latitude}, "
                    f"lon={longitude}, "
                    f"relative_alt={relative_altitude:.2f} m",
                    flush=True,
                )

    except KeyboardInterrupt:
        print("\nReceiver stopped.")


if __name__ == "__main__":
    main()