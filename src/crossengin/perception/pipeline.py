"""Text perception pipeline: ingest text, encode, buffer.

Per ADR-0004, perception is streaming. At M2 the surface is one async
method, ingest_text. M5/M6 cognitive callers will be the production
consumers.
"""

from __future__ import annotations

import asyncio
import time

from crossengin.perception.buffer import StreamingBuffer
from crossengin.perception.encoders.base import TextEncoder
from crossengin.perception.types import EncodedObservation, RawObservation


class TextPerceptionPipeline:
    """End-to-end text ingest path for M2."""

    def __init__(self, encoder: TextEncoder, buffer: StreamingBuffer) -> None:
        self._encoder = encoder
        self._buffer = buffer

    async def ingest_text(self, session_id: str, text: str) -> EncodedObservation:
        """Ingest a single text observation. Returns the encoded result.

        Encoding runs in a worker thread via asyncio.to_thread so the
        event loop is not blocked by CPU-bound torch operations.
        """
        if not session_id:
            raise ValueError("session_id must be non-empty")
        if not isinstance(text, str):
            raise TypeError("text must be a string")

        raw = RawObservation(
            timestamp=time.time(),
            session_id=session_id,
            modality="text",
            content=text,
        )
        embedding = await asyncio.to_thread(self._encoder.encode_one, text)
        obs = EncodedObservation(
            raw=raw,
            embedding=embedding,
            encoder_id=self._encoder.encoder_id,
        )
        await self._buffer.append(obs)
        return obs
