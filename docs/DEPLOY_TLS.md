# Deploying CrossEngin behind TLS (R54.1, ADR-0105)

This is the operator manual for putting a TLS sidecar in front of
`crossengin-rpc-daemon` so the JSON-RPC wire is encrypted.

TLS is delivered as a **sidecar recipe** — the daemon itself stays
TLS-unaware and bound to loopback; `stunnel` or `nginx` terminates
TLS and forwards decrypted bytes to the daemon. This decouples TLS
from NOVA (which has federation-side TLS but the socket-integration
story wants a round of smoothing before it's the daemon's default)
and reuses a battle-tested implementation.

**In-process TLS** for the daemon is R55+ future work; the sidecar
pattern is the ship-today answer.

## When you need this

- **Skip this entirely** if you're running the daemon on a single-user
  laptop for personal use. Loopback + no TLS is the correct default.
- **Do this** if you're binding the daemon on a LAN (multiple hosts
  can dial the port), a home lab, a shared box with untrusted users
  on the same network, or anywhere else where the socket isn't a
  private trust boundary.
- **Layer capability enforcement on top** (see
  [`docs/SHIP_AS_APP.md` §7.7](SHIP_AS_APP.md)). TLS gives you
  confidentiality; capabilities give you authorization. Both are
  independent — either alone is a partial defense.

## Threat model

TLS at the sidecar gives you:

- **Confidentiality** — a network eavesdropper (someone with
  `tcpdump` on a router hop) sees only encrypted bytes
- **Integrity** — an active MITM can't rewrite the wire mid-flight
- **Server authentication** — clients that check the cert know
  they're talking to the daemon they intended

TLS at the sidecar does NOT give you:

- **Client authentication** — anyone who can reach the socket can
  dispatch verbs. Use `CE_RPC_REQUIRE_TOKEN=1` for auth.
- **Sandboxing of installed skills** — a malicious skill is
  arbitrary code inside the daemon. Signed skill install (R54.2)
  is the mitigation.
- **Rate limiting** — a token holder can flood the daemon. R56+.

## 1. Generate a cert (dev / single-user)

For local + small-team use, ship the built-in helper:

```bash
scripts/gen_tls_cert.sh --host 127.0.0.1 --days 365
```

Writes to `~/.crossengin/tls/`:

```
server.key            ed25519 or RSA private key (0600)
server.pem            X.509 certificate (0644)
server-and-key.pem    concatenated (stunnel wants this shape)
```

The generated cert is **self-signed** — clients need to trust it
explicitly (see §3). For multi-user or public deployments, use a
real CA (§4).

Override the SAN with `--host your.hostname` when clients dial by
name rather than IP.

## 2. Configure a sidecar

Two reference configs ship in `infra/tls/`:

### stunnel

```bash
sudo cp infra/tls/stunnel.rpc.conf.example /etc/stunnel/crossengin.conf
sudo cp ~/.crossengin/tls/server-and-key.pem /etc/stunnel/crossengin.pem
sudo chmod 640 /etc/stunnel/crossengin.pem
sudo chown stunnel:stunnel /etc/stunnel/crossengin.pem
sudo systemctl restart stunnel@crossengin
```

### nginx (already on the box)

```bash
sudo cp infra/tls/nginx.rpc.conf.example /etc/nginx/conf.d/crossengin-rpc.stream.conf
sudo cp ~/.crossengin/tls/server.pem /etc/nginx/certs/crossengin.pem
sudo cp ~/.crossengin/tls/server.key /etc/nginx/certs/crossengin.key
sudo chmod 640 /etc/nginx/certs/crossengin.*
sudo chown root:www-data /etc/nginx/certs/crossengin.*
# nginx.conf must have `stream { include /etc/nginx/conf.d/*.stream.conf; }`
sudo nginx -t && sudo systemctl reload nginx
```

Both configs expose `:9977` (TLS) and forward to `127.0.0.1:9876`
(the plaintext daemon).

## 3. Boot the daemon

Bind the daemon to **loopback only** and enable capability
enforcement:

```bash
CE_RPC_BIND=127.0.0.1 \
CE_RPC_PORT=9876 \
CE_RPC_REQUIRE_TOKEN=1 \
CE_RPC_ADMIN_TOKEN_FILE=~/.crossengin/admin.token \
scripts/rpc_daemon.sh
```

Do **NOT** flip `CE_RPC_BIND_ALLOW_NON_LOOPBACK=1` on the daemon;
the sidecar is the ONLY ingress. If the daemon binds a routable
address, an attacker who bypasses the sidecar (arrives on the box
some other way) hits the plaintext wire directly.

## 4. Client connection

Because the sidecar terminates TLS on a raw-TCP forward (not HTTP),
the client speaks the SAME line-oriented JSON protocol, just wrapped
in a TLS handshake first. `scripts/rpc.sh` uses plain nc / bash
`/dev/tcp` and doesn't know about TLS; use `openssl s_client` or a
real TLS-aware socket client.

### openssl s_client

```bash
# Trust the self-signed cert; pipe a single JSON request line + \n.
printf '{"verb":"kg.list","token":"'"$CE_RPC_TOKEN"'"}\n' \
  | openssl s_client -quiet \
        -connect your.host:9977 \
        -CAfile ~/.crossengin/tls/server.pem \
        -verify_return_error \
        2>/dev/null
```

Response comes back as one JSON line.

### Python (stdlib only)

```python
import socket, ssl, json, os

ctx = ssl.create_default_context(cafile=os.path.expanduser("~/.crossengin/tls/server.pem"))
ctx.check_hostname = False   # IP-only SAN when host is a bare IP
sock = socket.create_connection(("your.host", 9977))
tls = ctx.wrap_socket(sock, server_hostname="your.host")
tls.sendall((json.dumps({
    "verb":  "kg.list",
    "token": os.environ["CE_RPC_TOKEN"],
}) + "\n").encode())
tls.shutdown(socket.SHUT_WR)
resp = b""
while chunk := tls.recv(65536):
    resp += chunk
print(json.loads(resp.decode()))
```

### Fingerprint pinning

For clients that can't manage a trust store, pin the cert's SHA-256
fingerprint (printed by `gen_tls_cert.sh`). Most TLS libraries
expose the peer cert; compare its `SHA-256` digest to the
known-good pin.

## 5. Public deployments (Let's Encrypt)

For internet-facing use, replace the self-signed cert with one
issued by a public CA. The sidecar config is unchanged; only the
cert path changes:

```bash
sudo certbot certonly --standalone --preferred-challenges http \
    -d rpc.your-domain.example
# -> /etc/letsencrypt/live/rpc.your-domain.example/{fullchain,privkey}.pem

# Point stunnel at the certbot output; certbot renews in place, so
# the sidecar picks up the new cert on next handshake (or restart).
# nginx: point ssl_certificate / ssl_certificate_key at fullchain +
# privkey; add a `certbot renew --deploy-hook 'systemctl reload nginx'`
# cron.
```

**Do not** run the LE-issued daemon without capability enforcement.
An open RPC wire on the public internet is arbitrary code execution.

## 6. Verifying the setup

```bash
# Should refuse plaintext connections (nc gets a garbage TLS handshake):
echo '{"verb":"kg.list"}' | nc your.host 9977
# -> silence or immediate close

# Should succeed:
printf '{"verb":"kg.list","token":"'"$CE_RPC_TOKEN"'"}\n' \
  | openssl s_client -quiet -connect your.host:9977 \
      -CAfile ~/.crossengin/tls/server.pem 2>/dev/null
# -> {"ok":true,"result":[...],"error":""}

# Should refuse a plaintext hit on the daemon's loopback port from a
# non-local host: the daemon is bound to 127.0.0.1 and rejects.
```

## 7. What R55+ replaces

- **In-process TLS** on the daemon (`src/federation/*` TLS layer
  integrated into `crossengin_rpc_daemon.nova`); once shipped the
  sidecar becomes optional.
- **`capability.issue` wire verb** so admin tokens can mint child
  tokens over the wire — today you mint them in-process from a
  small NOVA program that imports `src/sandbox/capability.nova`.
- **Rate limits per capability** attached to the token.

Everything R54.1 delivers today keeps working when those land;
R54.1 is additive scaffolding for the sidecar pattern.
