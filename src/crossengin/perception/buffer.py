"""In-memory streaming buffer of recent perception observations.

Per ADR-0004, perception is streaming and continuous. The buffer holds
the rolling window of recent observations. ADR-0004's open question on
backpressure policy (drop-oldest vs drop-newest vs summarize-and-collapse)
is resolved here as **drop-oldest** via deque(maxlen=...), with the
time-based eviction layered on top. This is the v0 default; the choice
may be revisited as the cognitive module's read pattern materializes.

The buffer is async-locked because the cognitive module will eventually
read it from an async event loop while the perception pipeline writes
from a worker thread.
"""

from __future__ import annotations

import asyncio
import time
from collections import deque

from crossengin.perception.types import EncodedObservation


class StreamingBuffer:
    """A rolling window of EncodedObservation values.

    Bounded by two limits:
    - max_items: hard upper bound on number of items kept (drop-oldest)
    - max_age_seconds: items older than this are evicted on access
    """

    def __init__(self, max_items: int = 256, max_age_seconds: float = 600.0) -> None:
        if max_items < 1:
            raise ValueError("max_items must be >= 1")
        if max_age_seconds <= 0:
            raise ValueError("max_age_seconds must be > 0")
        self._max_items = max_items
        self._max_age_seconds = max_age_seconds
        self._items: deque[EncodedObservation] = deque(maxlen=max_items)
        self._lock = asyncio.Lock()

    async def append(self, obs: EncodedObservation) -> None:
        async with self._lock:
            self._items.append(obs)
            self._evict_aged_locked()

    async def recent(self, n: int = 10) -> list[EncodedObservation]:
        if n < 0:
            raise ValueError("n must be >= 0")
        async with self._lock:
            self._evict_aged_locked()
            if n == 0:
                return []
            return list(self._items)[-n:]

    async def since(self, timestamp: float) -> list[EncodedObservation]:
        async with self._lock:
            self._evict_aged_locked()
            return [obs for obs in self._items if obs.raw.timestamp >= timestamp]

    async def all(self) -> list[EncodedObservation]:
        async with self._lock:
            self._evict_aged_locked()
            return list(self._items)

    async def size(self) -> int:
        async with self._lock:
            self._evict_aged_locked()
            return len(self._items)

    async def clear(self) -> None:
        async with self._lock:
            self._items.clear()

    def _evict_aged_locked(self) -> None:
        cutoff = time.time() - self._max_age_seconds
        while self._items and self._items[0].raw.timestamp < cutoff:
            self._items.popleft()
