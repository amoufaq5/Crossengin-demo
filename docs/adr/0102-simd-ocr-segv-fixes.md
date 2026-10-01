# ADR-0102: SIMD / OCR SEGV fixes — class-B outliers (R3c)

## Status

Accepted. Shipped by Phase Q R3c. Co-numbered with
`0102-persona.md` (per the two-ADR-0100 / two-ADR-0101 precedent).

## Context

Phase Q R3a (`6b746e7`, `docs/SEGFAULT_TRIAGE_R3A.md`) classified the
29-test SEGV cluster. R3b (`b64b382`, ADR-0101) handled class A
(`str_eq` short-literal flakiness). Class B — the 3 outliers deferred
to R3c — were `test_lk_u8_simd`, `test_lk_mulacc_simd`,
`test_image_ocr`.

R3a blamed `_lk_pack_block_u8` pointer drift. Explore disproved that:
it is byte-for-byte identical to `_stereo_pack_block_u8`, and R3a had
assumed `test_stereo_u8_simd` passed. Re-running at `b64b382` showed
stereo also SEGVs (same cause as LK, diagnosed below), so the plan's
regression canary is vacuous; the R3c fix does not touch stereo, so
stereo stays where R3b left it and rolls into R3d.

## Diagnosis

Per-test instrumentation (`println(int_to_str(ptr))` at each
`memcpy_raw` / `load8` / `s + buf` site, stripped before commit; raw
disassembly of the compiler's emitted call sequences) narrowed each
SEGV:

### test_lk_u8_simd — crashes on the first subtest's first `memcpy_raw`

- dmesg: `segfault at 0x8320ab ip 0x416559 error 4`,
  `Code: ... fc <f3> a4 58 c3` = `cld; <rep movsb>; pop rax; ret`.
- Printed args to the first `_lk_pack_block_u8` call (ws=7, flat
  16x16 image): `src_row=4296789`, `dst=4297232`, `n=7`. Both are
  heap addresses, 528 bytes apart — a 7-byte copy must not fault.
- Root cause (from `/home/user/NOVA/src/compiler/codegen.nova:22248`):
  `memcpy_raw` is a bare `push rdi; mov rcx, rdx; cld; rep movsb;
  pop rax; ret`. It does NOT untag its (rdi, rsi, rdx) args. NOVA
  ints and pointers are tagged `2x+1` (confirmed by inline `int_mul`
  = `lea rax,[rdi-1]; mov rcx,rsi; sar rcx,1; imul rax,rcx; inc
  rax`, and by `store8` / `load8` labels both doing `sar rdi, 1`).
  So `rep movsb` runs on tagged pointers (`actual*2+1`) which land
  in unmapped memory. The dmesg address 0x8320ab is roughly
  `2 * 0x41A010 + offset` — the "doubled" tagged form.

### test_lk_mulacc_simd — same root cause

Same transducer module, same lowering, four `memcpy_raw` calls per
pixel in `_lk_optical_flow_mulacc_inner`
(`image_optical_flow.nova:2503-2510`). Instrumentation showed the
identical SEGV signature at the first pack call.

### test_image_ocr — unrelated: `s + buf` with a raw byte buffer

- dmesg: `segfault at 0x2cd2f06 ip 0x409042`,
  `Code: 48 85 ff 74 1d <48 83 3f ff> 74 0d ...` =
  `test rdi,rdi; jz; <cmp qword [rdi],-1>; ...` — this is
  `_nova_check_rdi` from `codegen.nova:15777` (the type-probe
  `_nova_add` uses to pick int-add vs string concat).
- Bisection: `test_hello_round_trip` (subtest 11/12) is the crasher;
  the other 11 subtests pass with class-B gone.
- Site: `image_ocr.nova:504` — `s = s + buf` where `buf = alloc(2);
  store8(buf+0, char); store8(buf+1, 0)`. `buf` is a raw heap byte
  buffer with no NOVA runtime type header, so `_nova_add` dereferences
  through a tagged pointer-to-nowhere and faults.

## Decision

### LK pair — route around the broken builtin, not the builtin

Add `_lk_byte_copy(dst, src, n)` in `image_optical_flow.nova`:
`store8(dst+i, load8(src+i))` loop. `load8` / `store8` untag their
args, so the loop is tag-correct. Replace five `memcpy_raw` calls
in the LK pack paths with it (1 in `_lk_pack_block_u8`, 4 in
`_lk_optical_flow_mulacc_inner`). The constraint forbids editing
NOVA runtime, and the compiler label change — while technically
outside `src/runtime/*` — would affect every `memcpy_raw` caller
in the tree, so the per-caller workaround is lower blast radius.

Perf note: `memcpy_raw` was `rep movsb`; the replacement is a
byte-at-a-time loop. Slower, but correctness beats a crash; R3d
can restore the fast path once the untag is fixed.

### OCR — look the char up in a reference alphabet

Replace `alloc + store8 + s + buf` with a `substr` lookup into a
static `"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"`. `substr` returns a
proper NOVA string that `_nova_add`'s type probe accepts. The
default OCR gallery only emits char codes in `[48,57]` and
`[65,90]`, so the lookup covers every emittable character; unknown
codes drop out silently (same observable as the old path on noise).

## Consequences

Tests flipped PASS at R3c tip:
- `test_lk_u8_simd.nova` — 34 checks pass (13/13 subtests).
- `test_lk_mulacc_simd.nova` — 28 checks pass (11/11 subtests).
- `test_image_ocr.nova` — 40 checks pass (12/12 subtests).

No deferred subtests. No new regression on spot-checked tests
(`test_image_harris` fails the same 2/19 subtests as pre-R3c;
`test_image_tracker` fails the same 1 subtest as pre-R3c;
`test_stereo_u8_simd` still SEGVs — same bug as LK, same fix
pattern applies, out of R3c scope → R3d).

The LK pack path is scalar where it was `rep movsb`; the R15A perf
comments in `image_optical_flow.nova:613-631` are mildly stale.
R3d / a future runtime-fix round can revert to `memcpy_raw` once
the compiler untag is in.

## Follow-up (R3d)

- Fix NOVA's `memcpy_raw` codegen label (`codegen.nova:22248`) to
  untag its three args before `rep movsb` — `sar rdi,1; sar rsi,1;
  sar rdx,1`. Will flip `test_stereo_u8_simd` to PASS and let us
  revert `_lk_byte_copy` to `memcpy_raw` for the speed. Blocked on
  operator willingness to touch the NOVA compiler.
- The 15 non-str_eq SEGVs reclassified by R3b (parser / chunked-
  decode / alloc-buffer bugs) still await R3d.
