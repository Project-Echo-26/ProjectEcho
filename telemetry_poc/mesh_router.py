# AP_FLAKE8_CLEAN
"""Position-aware, multi-hop MAVLink telemetry router for local SITL tests."""

import argparse
import heapq
import itertools
import logging
import math
import random
import selectors
import socket
import struct
import time
from dataclasses import dataclass
from typing import Dict
from typing import List
from typing import Optional
from typing import Tuple


HEARTBEAT_ID = 0
GLOBAL_POSITION_INT_ID = 33
CRC_EXTRA = {
    HEARTBEAT_ID: 50,
    GLOBAL_POSITION_INT_ID: 104,
}
MAVLINK_V1_MAGIC = 0xFE
MAVLINK_V2_MAGIC = 0xFD
EARTH_RADIUS_M = 6371000.0
MeshPosition = Tuple[float, float, float]


@dataclass
class MavlinkFrame:
    system_id: int
    message_id: int
    payload: bytes
    raw: bytes


@dataclass
class MeshNode:
    system_id: int
    input_port: int
    output_port: int
    position: Optional[MeshPosition] = None
    position_updated_at: float = 0.0


def _x25_crc(data: bytes, crc_extra: int) -> int:
    crc = 0xFFFF
    for byte in data + bytes((crc_extra,)):
        tmp = byte ^ (crc & 0xFF)
        tmp ^= (tmp << 4) & 0xFF
        crc = ((crc >> 8) ^ (tmp << 8) ^ (tmp << 3) ^ (tmp >> 4)) & 0xFFFF
    return crc


def iter_mavlink_frames(datagram: bytes):
    """Yield valid HEARTBEAT and GLOBAL_POSITION_INT frames from a UDP datagram."""
    offset = 0
    while offset < len(datagram):
        while offset < len(datagram) and datagram[offset] not in (
            MAVLINK_V1_MAGIC,
            MAVLINK_V2_MAGIC,
        ):
            offset += 1
        if offset >= len(datagram):
            return

        magic = datagram[offset]
        payload_length = datagram[offset + 1] if offset + 1 < len(datagram) else 0
        if magic == MAVLINK_V1_MAGIC:
            header_length = 6
            if offset + header_length > len(datagram):
                return
            system_id = datagram[offset + 3]
            message_id = datagram[offset + 5]
            signature_length = 0
        else:
            header_length = 10
            if offset + header_length > len(datagram):
                return
            incompat_flags = datagram[offset + 2]
            if incompat_flags & ~0x01:
                offset += 1
                continue
            system_id = datagram[offset + 5]
            message_id = int.from_bytes(datagram[offset + 7 : offset + 10], "little")
            signature_length = 13 if incompat_flags & 0x01 else 0

        frame_length = header_length + payload_length + 2 + signature_length
        frame_end = offset + frame_length
        if frame_end > len(datagram):
            return

        crc_extra = CRC_EXTRA.get(message_id)
        if crc_extra is None:
            offset = frame_end
            continue

        payload_start = offset + header_length
        payload_end = payload_start + payload_length
        checksum = int.from_bytes(datagram[payload_end : payload_end + 2], "little")
        crc_data = datagram[offset + 1 : payload_end]
        if _x25_crc(crc_data, crc_extra) == checksum:
            yield MavlinkFrame(
                system_id=system_id,
                message_id=message_id,
                payload=datagram[payload_start:payload_end],
                raw=datagram[offset:frame_end],
            )
        offset = frame_end


def position_from_frame(frame: MavlinkFrame) -> Optional[MeshPosition]:
    if frame.message_id != GLOBAL_POSITION_INT_ID or not frame.payload:
        return None
    payload = frame.payload.ljust(20, b"\x00")
    latitude, longitude = struct.unpack_from("<ii", payload, 4)
    relative_altitude = struct.unpack_from("<i", payload, 16)[0]
    return latitude / 1e7, longitude / 1e7, relative_altitude / 1000.0


def distance_m(first: MeshPosition, second: MeshPosition) -> float:
    lat1, lon1, alt1 = first
    lat2, lon2, alt2 = second
    lat1 = math.radians(lat1)
    lat2 = math.radians(lat2)
    delta_lat = lat2 - lat1
    delta_lon = math.radians(lon2 - lon1)
    haversine = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(delta_lon / 2) ** 2
    )
    horizontal_distance = 2 * EARTH_RADIUS_M * math.asin(min(1.0, math.sqrt(haversine)))
    return math.hypot(horizontal_distance, alt2 - alt1)


class MeshRouter:
    def __init__(
        self,
        nodes: List[MeshNode],
        radio_range_m: float = 100.0,
        bandwidth_bps: float = 57600.0,
        latency_ms: float = 20.0,
        packet_loss: float = 0.01,
        max_hops: int = 4,
        position_timeout_s: float = 5.0,
        seed: int = 1,
    ):
        self.nodes = {node.system_id: node for node in nodes}
        self.radio_range_m = radio_range_m
        self.bandwidth_bps = bandwidth_bps
        self.latency_s = latency_ms / 1000.0
        self.packet_loss = packet_loss
        self.max_hops = max_hops
        self.position_timeout_s = position_timeout_s
        self._random = random.Random(seed)
        self._sequence = itertools.count()
        self._link_available_at: Dict[Tuple[int, int], float] = {}
        self._deliveries: List[Tuple[float, int, int, bytes]] = []
        self.frames_received = 0
        self.frames_delivered = 0
        self.loss_drops = 0
        self.unroutable_frames = 0

        if not nodes:
            raise ValueError("At least one mesh node is required")
        if len(self.nodes) != len(nodes):
            raise ValueError("Mesh node system IDs must be unique")
        if (
            not math.isfinite(radio_range_m)
            or not math.isfinite(bandwidth_bps)
            or radio_range_m <= 0
            or bandwidth_bps <= 0
        ):
            raise ValueError("Radio range and bandwidth must be positive")
        if (
            not math.isfinite(latency_ms)
            or not math.isfinite(packet_loss)
            or latency_ms < 0
            or not 0 <= packet_loss <= 1
        ):
            raise ValueError("Latency must be non-negative and packet loss must be in [0, 1]")
        if (
            not math.isfinite(position_timeout_s)
            or max_hops < 1
            or position_timeout_s <= 0
        ):
            raise ValueError("Hop limit and position timeout must be positive")

    def handle_datagram(self, system_id: int, datagram: bytes, now: float) -> None:
        node = self.nodes[system_id]
        for frame in iter_mavlink_frames(datagram):
            if frame.system_id != system_id:
                logging.warning(
                    "Ignoring MAVLink system ID %d on node %d input",
                    frame.system_id,
                    system_id,
                )
                continue

            self.frames_received += 1
            position = position_from_frame(frame)
            if position is not None:
                node.position = position
                node.position_updated_at = now
            self._broadcast(node.system_id, frame.raw, now)

    def _active_neighbors(self, now: float) -> Dict[int, List[int]]:
        active = {
            system_id: node.position
            for system_id, node in self.nodes.items()
            if node.position is not None
            and now - node.position_updated_at <= self.position_timeout_s
        }
        neighbors = {system_id: [] for system_id in active}
        for system_id, position in active.items():
            for other_id, other_position in active.items():
                if system_id != other_id and distance_m(position, other_position) <= self.radio_range_m:
                    neighbors[system_id].append(other_id)
        return neighbors

    def _broadcast(self, source_id: int, frame: bytes, now: float) -> None:
        neighbors = self._active_neighbors(now)
        if source_id not in neighbors:
            self.unroutable_frames += 1
            return

        visited = {source_id}
        in_flight = [(now, next(self._sequence), source_id, 0)]
        delivered = False

        while in_flight:
            arrival, _, current_id, hops = heapq.heappop(in_flight)
            if current_id != source_id:
                if current_id in visited:
                    continue
                visited.add(current_id)
                heapq.heappush(
                    self._deliveries,
                    (arrival, next(self._sequence), current_id, frame),
                )
                delivered = True

            if hops >= self.max_hops:
                continue
            for neighbor_id in neighbors.get(current_id, []):
                if neighbor_id in visited:
                    continue
                if self._random.random() < self.packet_loss:
                    self.loss_drops += 1
                    continue

                link = current_id, neighbor_id
                transmit_start = max(arrival, self._link_available_at.get(link, arrival))
                transmit_end = transmit_start + len(frame) * 8 / self.bandwidth_bps
                self._link_available_at[link] = transmit_end
                neighbor_arrival = transmit_end + self.latency_s
                heapq.heappush(
                    in_flight,
                    (neighbor_arrival, next(self._sequence), neighbor_id, hops + 1),
                )

        if not delivered:
            self.unroutable_frames += 1

    def pop_due(self, now: float) -> List[Tuple[int, bytes]]:
        due = []
        while self._deliveries and self._deliveries[0][0] <= now:
            _, _, system_id, frame = heapq.heappop(self._deliveries)
            due.append((system_id, frame))
            self.frames_delivered += 1
        return due

    def next_delivery_at(self) -> Optional[float]:
        if not self._deliveries:
            return None
        return self._deliveries[0][0]


def parse_node(value: str) -> MeshNode:
    try:
        system_id, input_port, output_port = (int(part) for part in value.split(":"))
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Use SYSTEM_ID:INPUT_PORT:OUTPUT_PORT") from exc
    if not 1 <= system_id <= 255:
        raise argparse.ArgumentTypeError("System ID must be in [1, 255]")
    if not 1 <= input_port <= 65535 or not 1 <= output_port <= 65535:
        raise argparse.ArgumentTypeError("UDP ports must be in [1, 65535]")
    return MeshNode(system_id, input_port, output_port)


def parse_udp_destination(value: str) -> Tuple[str, int]:
    try:
        host, port_text = value.rsplit(":", 1)
        port = int(port_text)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Use HOST:PORT for the GCS UDP destination") from exc
    if not host or ":" in host or not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError("Use a valid IPv4/hostname and UDP port")
    return host, port


def send_mesh_frame(
    output_socket: socket.socket,
    frame: bytes,
    peer_destination: Tuple[str, int],
    gcs_destination: Optional[Tuple[str, int]],
) -> None:
    output_socket.sendto(frame, peer_destination)
    if gcs_destination is not None:
        output_socket.sendto(frame, gcs_destination)


def run(args: argparse.Namespace) -> None:
    nodes = args.node
    ports = [node.input_port for node in nodes] + [node.output_port for node in nodes]
    if len(set(ports)) != len(ports):
        raise ValueError("All mesh input and output ports must be unique")

    router = MeshRouter(
        nodes,
        radio_range_m=args.range_m,
        bandwidth_bps=args.bandwidth,
        latency_ms=args.latency_ms,
        packet_loss=args.packet_loss,
        max_hops=args.max_hops,
        position_timeout_s=args.position_timeout,
        seed=args.seed,
    )
    selector = selectors.DefaultSelector()
    sockets: Dict[int, socket.socket] = {}
    output_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    try:
        for node in nodes:
            input_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            input_socket.bind(("127.0.0.1", node.input_port))
            input_socket.setblocking(False)
            sockets[node.system_id] = input_socket
            selector.register(input_socket, selectors.EVENT_READ, node.system_id)

        logging.info(
            "Mesh router active: range %.1f m, bandwidth %.0f bit/s, latency %.1f ms, "
            "loss %.1f%%, max hops %d",
            args.range_m,
            args.bandwidth,
            args.latency_ms,
            args.packet_loss * 100,
            args.max_hops,
        )
        if args.gcs_output is not None:
            logging.info(
                "Mesh-forwarded telemetry also sent to GCS %s:%d",
                args.gcs_output[0],
                args.gcs_output[1],
            )
        for node in nodes:
            logging.info(
                "System %d: MAVProxy input 127.0.0.1:%d -> peer receiver 127.0.0.1:%d",
                node.system_id,
                node.input_port,
                node.output_port,
            )

        while True:
            next_delivery = router.next_delivery_at()
            timeout = 0.1 if next_delivery is None else max(
                0.0, min(0.1, next_delivery - time.monotonic())
            )
            for key, _ in selector.select(timeout):
                node_id = key.data
                datagram, _ = key.fileobj.recvfrom(65535)
                router.handle_datagram(node_id, datagram, time.monotonic())

            now = time.monotonic()
            for destination_id, frame in router.pop_due(now):
                destination = router.nodes[destination_id]
                send_mesh_frame(
                    output_socket,
                    frame,
                    ("127.0.0.1", destination.output_port),
                    args.gcs_output,
                )
    finally:
        selector.close()
        output_socket.close()
        for input_socket in sockets.values():
            input_socket.close()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Simulate a range-limited, multi-hop MAVLink telemetry mesh for SITL."
    )
    parser.add_argument(
        "--node",
        action="append",
        type=parse_node,
        required=True,
        metavar="SYSTEM_ID:INPUT_PORT:OUTPUT_PORT",
        help="MAVProxy UDP input and peer telemetry receiver port; repeat per drone",
    )
    parser.add_argument(
        "--gcs-output",
        type=parse_udp_destination,
        metavar="HOST:PORT",
        help="also send mesh-forwarded telemetry to a ground station (read-only)",
    )
    parser.add_argument("--range-m", type=float, default=100.0, help="Radio range in meters")
    parser.add_argument(
        "--bandwidth",
        type=float,
        default=57600.0,
        help="Per-link bandwidth in bits per second",
    )
    parser.add_argument("--latency-ms", type=float, default=20.0, help="Per-hop latency")
    parser.add_argument(
        "--packet-loss",
        type=float,
        default=0.01,
        help="Independent per-hop packet loss probability from 0 to 1",
    )
    parser.add_argument("--max-hops", type=int, default=4, help="Maximum relay hops")
    parser.add_argument(
        "--position-timeout",
        type=float,
        default=5.0,
        help="Seconds before a node's last position is considered stale",
    )
    parser.add_argument("--seed", type=int, default=1, help="Seed for repeatable packet loss")
    parser.add_argument("--verbose", action="store_true", help="Enable debug logging")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    run(args)


if __name__ == "__main__":
    main()
