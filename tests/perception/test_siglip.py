"""Integration test for the real SigLIP encoder.

Marked @pytest.mark.integration. Skipped by default in fast runs; opt
in with `uv run pytest -m integration`.

The first run downloads ~400MB of model weights to the HuggingFace
cache. Subsequent runs are fast.
"""

from __future__ import annotations

import numpy as np
import pytest

from crossengin.perception import (
    SigLIPTextEncoder,
    StreamingBuffer,
    TextPerceptionPipeline,
)


@pytest.mark.integration
async def test_siglip_round_trip() -> None:
    """The M2 exit-criterion check, using the real SigLIP encoder."""
    encoder = SigLIPTextEncoder()
    assert encoder.embedding_dim == 768
    assert encoder.encoder_id == "google/siglip-base-patch16-224"

    buffer = StreamingBuffer()
    pipeline = TextPerceptionPipeline(encoder=encoder, buffer=buffer)

    obs = await pipeline.ingest_text(session_id="t", text="the patient has hypertension")

    assert obs.embedding.shape == (768,)
    assert obs.embedding.dtype == np.float32
    norm = float(np.linalg.norm(obs.embedding))
    assert pytest.approx(norm, rel=1e-3) == 1.0

    landed = await buffer.recent(1)
    assert len(landed) == 1
    assert landed[0].raw.content == "the patient has hypertension"
    assert landed[0].encoder_id == "google/siglip-base-patch16-224"


@pytest.mark.integration
def test_siglip_batch_encoding() -> None:
    encoder = SigLIPTextEncoder()
    texts = ["aspirin treats headaches", "warfarin is an anticoagulant"]
    embeddings = encoder.encode(texts)
    assert embeddings.shape == (2, 768)
    assert embeddings.dtype == np.float32
    assert not np.allclose(embeddings[0], embeddings[1])


@pytest.mark.integration
def test_siglip_empty_batch_returns_empty() -> None:
    encoder = SigLIPTextEncoder()
    out = encoder.encode([])
    assert out.shape == (0, 768)
