# AP_FLAKE8_CLEAN

import math
import struct
import unittest

from mesh_router import EARTH_RADIUS_M
from mesh_router import GLOBAL_POSITION_INT_ID
from mesh_router import HEARTBEAT_ID
from mesh_router import MeshNode
from mesh_router import MeshRouter
from mesh_router import _x25_crc
from mesh_router import iter_mavlink_frames


CRC_EXTRA = {
    HEARTBEAT_ID: 50,
    GLOBAL_POSITION_INT_ID: 104,
}


def make_frame(system_id, message_id, payload, version=1):
    if version == 1:
        header = bytes((len(payload), 0, system_id, 1, message_id))
        checksum = _x25_crc(header + payload, CRC_EXTRA[message_id])
        return bytes((0xFE,)) + header + payload + struct.pack("<H", checksum)

    payload = payload.rstrip(b"\x00") or payload[:1]
    header = bytes(
        (
            len(payload),
            0,
            0,
            0,
            system_id,
            1,
            message_id & 0xFF,
            (message_id >> 8) & 0xFF,
            (message_id >> 16) & 0xFF,
        )
    )
    checksum = _x25_crc(header + payload, CRC_EXTRA[message_id])
    return bytes((0xFD,)) + header + payload + struct.pack("<H", checksum)


def global_position_frame(system_id, east_m, version=1):
    payload = bytearray(28)
    longitude = round(east_m / EARTH_RADIUS_M * 1e7)
    struct.pack_into("<ii", payload, 4, 0, longitude)
    return make_frame(system_id, GLOBAL_POSITION_INT_ID, payload, version)


class MeshRouterTest(unittest.TestCase):
    def make_router(self, east_positions, **kwargs):
        kwargs.setdefault("bandwidth_bps", 1e9)
        kwargs.setdefault("latency_ms", 20)
        kwargs.setdefault("packet_loss", 0)
        nodes = [
            MeshNode(
                system_id,
                14610 + system_id,
                14620 + system_id,
                position=(0.0, math.degrees(east_m / EARTH_RADIUS_M), 0.0),
                position_updated_at=0.0,
            )
            for system_id, east_m in enumerate(east_positions, start=1)
        ]
        return MeshRouter(nodes, **kwargs)

    def test_parser_accepts_valid_mavlink_v1_and_v2_frames(self):
        payload = bytes(9)
        for version in (1, 2):
            frame = make_frame(1, HEARTBEAT_ID, payload, version)
            parsed = list(iter_mavlink_frames(frame))
            self.assertEqual(len(parsed), 1)
            self.assertEqual(parsed[0].raw, frame)
            self.assertEqual(parsed[0].system_id, 1)

    def test_position_parser_handles_mavlink_v2_trailing_zero_truncation(self):
        router = self.make_router([0, 3], radio_range_m=100)
        frame = global_position_frame(1, 0, version=2)
        router.handle_datagram(1, frame, 0.0)

        self.assertEqual([system_id for system_id, _ in router.pop_due(1.0)], [2])

    def test_parser_rejects_corrupted_checksum(self):
        frame = bytearray(make_frame(1, HEARTBEAT_ID, bytes(9)))
        frame[-3] ^= 0x01
        self.assertEqual(list(iter_mavlink_frames(frame)), [])

    def test_command_messages_are_not_forwarded(self):
        router = self.make_router([0, 3], radio_range_m=100)
        command_payload = bytes(33)
        command_frame = bytes((0xFE, len(command_payload), 0, 1, 1, 76))
        command_frame += command_payload + bytes(2)
        router.handle_datagram(1, command_frame, 0.0)

        self.assertEqual(router.frames_received, 0)
        self.assertEqual(router.pop_due(1.0), [])

    def test_delivers_to_direct_neighbor_after_one_hop_delay(self):
        router = self.make_router([0, 3], radio_range_m=100)
        router.handle_datagram(1, global_position_frame(1, 0), 0.0)

        self.assertEqual(router.pop_due(0.019), [])
        due = router.pop_due(0.021)
        self.assertEqual([system_id for system_id, _ in due], [2])

    def test_does_not_deliver_outside_radio_range(self):
        router = self.make_router([0, 101], radio_range_m=100)
        router.handle_datagram(1, global_position_frame(1, 0), 0.0)

        self.assertEqual(router.pop_due(1.0), [])
        self.assertEqual(router.unroutable_frames, 1)

    def test_relays_to_two_hops_but_obeys_hop_limit(self):
        router = self.make_router([0, 80, 160], radio_range_m=100, max_hops=2)
        router.handle_datagram(1, global_position_frame(1, 0), 0.0)

        due = router.pop_due(1.0)
        self.assertEqual({system_id for system_id, _ in due}, {2, 3})

    def test_hop_limit_one_does_not_relay_to_a_second_neighbor(self):
        router = self.make_router([0, 80, 160], radio_range_m=100, max_hops=1)
        router.handle_datagram(1, global_position_frame(1, 0), 0.0)

        due = router.pop_due(1.0)
        self.assertEqual({system_id for system_id, _ in due}, {2})

    def test_bandwidth_adds_serialization_delay(self):
        router = self.make_router(
            [0, 3],
            radio_range_m=100,
            bandwidth_bps=1000,
            latency_ms=20,
        )
        frame = global_position_frame(1, 0)
        router.handle_datagram(1, frame, 0.0)

        self.assertEqual(router.pop_due(0.30), [])
        self.assertEqual([system_id for system_id, _ in router.pop_due(0.31)], [2])

    def test_stale_position_removes_a_node_from_mesh(self):
        router = self.make_router([0, 3], radio_range_m=100, position_timeout_s=1.0)
        router.handle_datagram(1, global_position_frame(1, 0), 2.0)

        self.assertEqual(router.pop_due(3.0), [])
        self.assertEqual(router.unroutable_frames, 1)

    def test_packet_loss_can_drop_every_transmission(self):
        router = self.make_router([0, 3], radio_range_m=100, packet_loss=1.0)
        router.handle_datagram(1, global_position_frame(1, 0), 0.0)

        self.assertEqual(router.pop_due(1.0), [])
        self.assertEqual(router.loss_drops, 1)


if __name__ == "__main__":
    unittest.main()
