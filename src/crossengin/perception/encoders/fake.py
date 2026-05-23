"""Deterministic fake encoder for unit tests.

Does not load any model. Produces stable embeddings derived from a hash
of the input text. Used by buffer, pipeline, and downstream tests to
avoid SigLIP download cost and inference latency.
"""

from __future__ import annotations

import hashlib

import numpy as np

from crossengin.perception.encoders.base import TextEncoder
from crossengin.perception.types import Embedding


class FakeTextEncoder(TextEncoder):
    """Deterministic, fast, dependency-free encoder."""

    ENCODER_ID = "fake-encoder-v0"
    EMBEDDING_DIM = 16

    @property
    def encoder_id(self) -> str:
        return self.ENCODER_ID

    @property
    def embedding_dim(self) -> int:
        return self.EMBEDDING_DIM

    def encode(self, texts: list[str]) -> Embedding:
        if not texts:
            return np.empty((0, self.embedding_dim), dtype=np.float32)
        out = np.zeros((len(texts), self.embedding_dim), dtype=np.float32)
        # sha512 yields 64 bytes = 16 uint32 values, matching EMBEDDING_DIM.
        for i, text in enumerate(texts):
            digest = hashlib.sha512(text.encode("utf-8")).digest()
            raw = np.frombuffer(digest[: 4 * self.embedding_dim], dtype=np.uint32)
            vec = (raw.astype(np.float32) / np.iinfo(np.uint32).max).astype(np.float32)
            norm = float(np.linalg.norm(vec))
            if norm > 0:
                vec = vec / norm
            out[i] = vec
        return out
