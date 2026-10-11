# Maker publication replay/control audit

**PASS for frozen candidate-v2 under the sealed Python runtime. No open findings within this scope.**

No Sui, build/test, RPC, signing or Git commands were executed by this reviewer. Review used offline hashing, parsing and in-memory validation only.

## Frozen identity

- Config SHA256: `597b076d00a577d8c6b4545851130a6f1260bce37d49eb70941775ed3031f1d2`
- Seal SHA256: `8638c9a2f8e3cb75ea73826bf2ff91ad5d668b3af5ea72e84523a3409f9342d1`
- Python: sealed bundled 3.12.14, SHA256 `2498a31965647f1507a53e391842b23c29d96f0ef4550475f34a1d2b30c23ddb`

## Resolved findings

- RPCONTROL-01: All ten assertions were replaced with explicit require/ValueError checks. No validation assert remains. Independent normal/optimize1/optimize2 checks reject malformed manifests, locators, lock digests and edges.
- RPCONTROL-02: Selected bundled Python 3.12.14 path, resolved binary, SHA and version are sealed; load_controls verifies them. Config explicitly makes no default-python3 compatibility claim. Coordinator must install/verify its default-Python launcher selecting this sealed runtime before actual replay.
- RPCONTROL-03: Actual mode now requires all 217 original inputs to match actual_original_inputs. Independent recomputation shows 183 paths derive exactly from reviewed payload, including 63 changed hashes; all 34 unaffected historical paths retain original pins.
- RPCONTROL-04: refusal_diagnostic now requires the first diagnostic code and first primary source location. Independent expected-code/wrong-first/right-secondary and wrong-first-code/later-right cases reject in all optimization modes; all 16 historical real refusal logs still satisfy the stricter predicate.

## Verified evidence

- All 39 sealed controls, config/seal freeze, 254 candidate hashes, 254 payload hashes, 217 still-frozen originals and 20,268 cached compiler inputs match.
- Payload-map/config correspondence is exact. All 170 Move source/test files preserve byte identity. Candidate and reviewed actual payload normalize to the same stage bytes for all 254 files; 274 local lock checks pass.
- No existing v1 config fields changed. V2 only adds explicit runtime/original/control metadata; source and payload inputs are unchanged.
- Writer evidence records 51 offline checks passing across normal, -O and -OO. The reviewer independently checked 15 guards per mode (45 total), including malformed dependency fields/replacements, alias collisions, lock digest/edge, config/control/runtime tampering and refusal diagnostic ordering.
- All 16 historical real refusal logs pass the v2 first-source predicate in every mode. Existing v1 recorded 45 commands remain historical; the reviewer did not rerun them.

## Scope and remaining acceptance

Actual import, actual default-Python launcher and actual v2 replay have not been verified. The coordinator must copy the reviewed main/helper/config bytes, retarget only installed seal control paths, verify its launcher selects the sealed runtime, then run the authorized single 45-command actual staged replay. Config explicitly does not claim direct default-python3 compatibility.

Published compatibility, full manufacturing, full-product completion and Release/Deploy remain unproven. Original owners, continuation pointer and authorization boundaries are unchanged. Handbook v1.0 (2026-10-06), sections 1–5, 7, 8.1/8.3/8.4, 9 and 12 apply.
