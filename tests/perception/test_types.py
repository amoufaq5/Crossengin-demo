"""Tests for perception data types."""

from __future__ import annotations

import numpy as np
import pytest

from crossengin.perception import EncodedObservation, RawObservation


def test_raw_observation_is_frozen() -> None:
    obs = RawObservation(
        timestamp=1.0,
        session_id="s1",
        modality="text",
        content="hello",
    )
    with pytest.raises(AttributeError):
        obs.session_id = "s2"  # type: ignore[misc]


def test_encoded_observation_carries_embedding() -> None:
    raw = RawObservation(timestamp=1.0, session_id="s", modality="text", content="x")
    emb = np.ones(4, dtype=np.float32)
    obs = EncodedObservation(raw=raw, embedding=emb, encoder_id="fake")
    assert obs.embedding.shape == (4,)
    assert obs.embedding.dtype == np.float32
    assert obs.encoder_id == "fake"
