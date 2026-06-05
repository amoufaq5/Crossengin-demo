"use client";

import { useEffect, useRef, useState } from "react";

type Turn = {
  role: "user" | "agent";
  text: string;
};

/**
 * Minimal chat UI for the Vercel-hybrid CrossEngin pattern.
 *
 * Posts {session_id, input} to /api/chat (a Vercel Function defined under
 * app/api/chat/route.ts), which forwards to the self-hosted CrossEngin
 * backend over HTTPS. We render the streamed response body incrementally,
 * matching how `bin/crossengin` produces its `agent>` line.
 */
export default function ChatPage() {
  const [turns, setTurns] = useState<Turn[]>([]);
  const [input, setInput] = useState("");
  const [pending, setPending] = useState(false);
  const sessionId = useRef<string>("");

  useEffect(() => {
    // Stable per-tab session id. The backend is single-user in v1 (see
    // GETTING_STARTED.md Section 5), so this is mostly informational --
    // the wrapper still spawns a fresh `bin/crossengin` per turn.
    if (!sessionId.current) {
      sessionId.current =
        typeof crypto !== "undefined" && "randomUUID" in crypto
          ? crypto.randomUUID()
          : `s-${Date.now().toString(36)}`;
    }
  }, []);

  async function send() {
    const text = input.trim();
    if (!text || pending) return;
    setInput("");
    setTurns((prev) => [...prev, { role: "user", text }]);
    setPending(true);

    try {
      const resp = await fetch("/api/chat", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ session_id: sessionId.current, input: text }),
      });

      if (!resp.ok || !resp.body) {
        const detail = await resp.text().catch(() => "");
        setTurns((prev) => [
          ...prev,
          {
            role: "agent",
            text: `[backend ${resp.status}] ${detail || "no body"}`,
          },
        ]);
        return;
      }

      const reader = resp.body.getReader();
      const decoder = new TextDecoder();
      let acc = "";
      // Insert a placeholder turn we mutate as chunks arrive.
      setTurns((prev) => [...prev, { role: "agent", text: "" }]);
      // Stream until upstream closes. Each chunk is whatever the
      // CrossEngin wrapper flushed -- typically the `agent>` line + trace.
      // eslint-disable-next-line no-constant-condition
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        acc += decoder.decode(value, { stream: true });
        setTurns((prev) => {
          const next = prev.slice();
          next[next.length - 1] = { role: "agent", text: acc };
          return next;
        });
      }
    } catch (err) {
      setTurns((prev) => [
        ...prev,
        { role: "agent", text: `[network error] ${(err as Error).message}` },
      ]);
    } finally {
      setPending(false);
    }
  }

  function onKey(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      void send();
    }
  }

  return (
    <main style={{ maxWidth: 720, margin: "2rem auto", padding: "0 1rem" }}>
      <h1 style={{ marginBottom: "0.25rem" }}>CrossEngin</h1>
      <p style={{ color: "#666", marginTop: 0 }}>
        Vercel-hosted front end. Each turn spawns a fresh agent on the
        backend (see <code>scripts/chat.sh</code>).
      </p>
      <section
        aria-label="conversation"
        style={{
          border: "1px solid #ddd",
          borderRadius: 6,
          padding: "0.75rem",
          minHeight: 280,
          marginBottom: "0.75rem",
          background: "#fafafa",
        }}
      >
        {turns.length === 0 ? (
          <p style={{ color: "#999", fontStyle: "italic" }}>
            No turns yet. Try &quot;hello&quot; or &quot;fever&quot;.
          </p>
        ) : (
          turns.map((t, i) => (
            <div key={i} style={{ marginBottom: "0.5rem" }}>
              <strong>{t.role === "user" ? "you" : "agent"}&gt;</strong>{" "}
              <span style={{ whiteSpace: "pre-wrap" }}>{t.text}</span>
            </div>
          ))
        )}
      </section>
      <div style={{ display: "flex", gap: "0.5rem" }}>
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={onKey}
          placeholder="say something..."
          disabled={pending}
          style={{
            flex: 1,
            padding: "0.5rem 0.75rem",
            border: "1px solid #ccc",
            borderRadius: 4,
            fontSize: 16,
          }}
        />
        <button
          onClick={send}
          disabled={pending || input.trim().length === 0}
          style={{
            padding: "0.5rem 1rem",
            border: "none",
            borderRadius: 4,
            background: pending ? "#999" : "#333",
            color: "white",
            cursor: pending ? "wait" : "pointer",
            fontSize: 16,
          }}
        >
          {pending ? "..." : "Send"}
        </button>
      </div>
    </main>
  );
}
