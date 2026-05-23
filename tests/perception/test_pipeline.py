"""Tests for TextPerceptionPipeline using the FakeTextEncoder."""

from __future__ import annotations

import numpy as np
import pytest

from crossengin.perception import TextPerceptionPipeline


async def test_ingest_text_returns_encoded_observation(
    fake_pipeline: TextPerceptionPipeline,
) -> None:
    obs = await fake_pipeline.ingest_text(session_id="s", text="hello")
    assert obs.raw.content == "hello"
    assert obs.raw.modality == "text"
    assert obs.raw.session_id == "s"
    assert obs.embedding.shape == (16,)
    assert obs.embedding.dtype == np.float32


async def test_round_trip_through_buffer(
    fake_pipeline: TextPerceptionPipeline,
) -> None:
    """The M2 exit-criterion check, using the fake encoder for speed."""
    await fake_pipeline.ingest_text(session_id="s", text="hello world")
    recent = await fake_pipeline._buffer.recent(1)
    assert len(recent) == 1
    landed = recent[0]
    assert landed.raw.content == "hello world"
    assert landed.embedding.shape == (16,)
    assert pytest.approx(float(np.linalg.norm(landed.embedding)), rel=1e-3) == 1.0


async def test_empty_session_id_rejected(
    fake_pipeline: TextPerceptionPipeline,
) -> None:
    with pytest.raises(ValueError, match="session_id must be non-empty"):
        await fake_pipeline.ingest_text(session_id="", text="x")
