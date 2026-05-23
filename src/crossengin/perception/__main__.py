"""CLI demo for the M2 text perception pipeline.

Usage:
    uv run python -m crossengin.perception "hello world"

Prints the embedding shape, dtype, norm, and the buffer's view of
the observation. Useful for manually verifying the M2 exit gate.
"""

from __future__ import annotations

import asyncio
import sys

import numpy as np

from crossengin.perception import (
    SigLIPTextEncoder,
    StreamingBuffer,
    TextPerceptionPipeline,
)


async def main(text: str) -> int:
    print("Loading SigLIP encoder (downloads ~400MB on first use)...", file=sys.stderr)
    encoder = SigLIPTextEncoder()
    buffer = StreamingBuffer()
    pipeline = TextPerceptionPipeline(encoder=encoder, buffer=buffer)

    print(f"Ingesting: {text!r}", file=sys.stderr)
    obs = await pipeline.ingest_text(session_id="cli-demo", text=text)

    print(f"Encoder:         {obs.encoder_id}")
    print(f"Embedding shape: {obs.embedding.shape}")
    print(f"Embedding dtype: {obs.embedding.dtype}")
    print(f"Embedding norm:  {float(np.linalg.norm(obs.embedding)):.6f}")
    print(f"First 8 values:  {obs.embedding[:8].tolist()}")

    recent = await buffer.recent(5)
    print(f"\nBuffer holds {len(recent)} item(s):")
    for r in recent:
        snippet = r.raw.content if isinstance(r.raw.content, str) else "<bytes>"
        print(f"  [{r.raw.timestamp:.3f}] {r.raw.session_id}: {snippet!r}")

    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python -m crossengin.perception <text>", file=sys.stderr)
        sys.exit(1)
    raise SystemExit(asyncio.run(main(" ".join(sys.argv[1:]))))
