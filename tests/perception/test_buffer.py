"""Tests for StreamingBuffer."""

from __future__ import annotations

import asyncio

import numpy as np
import pytest

from crossengin.perception import (
    EncodedObservation,
    RawObservation,
    StreamingBuffer,
)


def _make_obs(text: str, ts: float = 1.0) -> EncodedObservation:
    raw = RawObservation(timestamp=ts, session_id="s", modality="text", content=text)
    return EncodedObservation(
        raw=raw,
        embedding=np.ones(4, dtype=np.float32),
        encoder_id="fake",
    )


async def test_append_and_recent() -> None:
    import time

    buf = StreamingBuffer(max_items=10)
    now = time.time()
    await buf.append(_make_obs("a", ts=now))
    await buf.append(_make_obs("b", ts=now))
    recent = await buf.recent(5)
    assert len(recent) == 2
    assert recent[-1].raw.content == "b"


async def test_capacity_bound_evicts_oldest() -> None:
    import time

    buf = StreamingBuffer(max_items=2)
    now = time.time()
    await buf.append(_make_obs("a", ts=now))
    await buf.append(_make_obs("b", ts=now))
    await buf.append(_make_obs("c", ts=now))
    items = await buf.all()
    assert [i.raw.content for i in items] == ["b", "c"]


async def test_age_bound_evicts_stale() -> None:
    import time

    buf = StreamingBuffer(max_items=10, max_age_seconds=0.05)
    now = time.time()
    await buf.append(_make_obs("old", ts=now))
    await asyncio.sleep(0.1)
    await buf.append(_make_obs("new", ts=time.time()))
    items = await buf.all()
    assert [i.raw.content for i in items] == ["new"]


async def test_clear_removes_all() -> None:
    import time

    buf = StreamingBuffer()
    await buf.append(_make_obs("a", ts=time.time()))
    await buf.clear()
    assert await buf.size() == 0


def test_invalid_max_items_raises() -> None:
    with pytest.raises(ValueError, match="max_items must be >= 1"):
        StreamingBuffer(max_items=0)


def test_invalid_max_age_raises() -> None:
    with pytest.raises(ValueError, match="max_age_seconds must be > 0"):
        StreamingBuffer(max_age_seconds=0)
