import pytest

from app.frame import FLAG_BRIGADISTA, FRAME_SIZE, Frame, FrameError

GOLDEN_HEX = "010100038403070000f15365f84b3301402df8f90904004c78"


def golden_frame() -> Frame:
    return Frame(
        flags=FLAG_BRIGADISTA,
        kind=0,
        node_id=900,
        seq=7,
        node_time=1_700_000_000,
        lat=20.139,
        lon=-101.176,
        severity=9,
        affected=4,
        ttl=3,
    )


def test_frame_is_well_under_budget():
    assert FRAME_SIZE == 25
    assert FRAME_SIZE < 200


def test_golden_vector_matches():
    assert golden_frame().encode().hex() == GOLDEN_HEX


def test_roundtrip_preserves_fields():
    decoded = Frame.decode(bytes.fromhex(GOLDEN_HEX))
    assert decoded == golden_frame()
    assert decoded.verified


def test_citizen_frame_is_not_verified():
    frame = Frame(flags=0, kind=1, node_id=1, seq=1, node_time=10, lat=20.0, lon=-101.0)
    assert not Frame.decode(frame.encode()).verified


def test_corrupted_byte_is_rejected():
    raw = bytearray(bytes.fromhex(GOLDEN_HEX))
    raw[10] ^= 0xFF
    with pytest.raises(FrameError, match="CRC"):
        Frame.decode(bytes(raw))


def test_wrong_length_is_rejected():
    with pytest.raises(FrameError, match="longitud"):
        Frame.decode(bytes.fromhex(GOLDEN_HEX)[:-1])


def test_unknown_kind_is_rejected():
    frame = Frame(flags=0, kind=99, node_id=1, seq=1, node_time=10, lat=20.0, lon=-101.0)
    with pytest.raises(FrameError, match="tipo"):
        Frame.decode(frame.encode())
