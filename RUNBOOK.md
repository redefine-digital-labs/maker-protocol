# Operation, failure, and recovery

1. Pin the candidate's source/diff, dependency locks, configuration/artifact digests, environment/network, relevant packages/objects, and consumers in the original record.
2. Run this repository's CI and registered product commands; retain logs and summaries. Unregistered, unperformed, or failed gates must not be rewritten as passed.
3. An actual independent acceptor checks the exact combination and recovery. release-ready checks material completeness; final approval still follows original authorization.
4. Authorized executors perform production deployment, upgrades, initialization, and signing at the exact target and read back the result. This template does not automatically perform these operations.
5. For failures, record the original intent/digest, effects, paid resources, and checkpoints. Query the original result first when the outcome is unknown. A readback failure after success does not make the result unknown; do not repeat minting/upload/payment.
6. Frontends/SDKs can revert to pinned artifacts; do not assume on-chain state, transfers, or upgrades are reversible. Verify the actual actions covered by pause/resume and lawful exits individually.
7. Attach the handoff to the original record, retaining source candidates/evidence/remaining conditions. Release exclusive resources such as wallets, browsers, and deployment environments. Stopping an executor does not delete historical assets or paid resources.

Operational responsibilities, monitoring sources/windows/thresholds, recovery drills, and actual production targets remain pending until established. Without actual observations, do not claim monitoring is enabled.
Tooling repositories do not own business operational gates. Handle cross-repository failures for the exact affected combination and hand off to the relevant maintainer.

## Current local verification and recovery

The current product command is scripts/run_maker_publication.py; module.json pins configuration and seal. The default Python3.9 launcher checks pinned Python3.12 before running the verifier. Optimization flags must not bypass assert checks; current tooling uses explicit rejection. One current 45-command proof is retained; documentation updates do not require repeating VM execution.

The current proof is staged replay of byte-identical installed inputs, redirecting only local locations and corresponding digests. Future independent CI should narrow to actual consumption contracts; cross-repository combinations belong to Integration. Old two-leaf-package commands/artifacts remain historical and do not prove current inputs.

Recovery material is in the actual worktree's maker-publication-extraction: 63 independent before copies for 134 imported files, complete 254-input payload, and 13 unchanged locations. Independent Content manifest/lock fixes have separate source-transition-registered.json and actual before copies. Verify current SHA and sole writer first, then restore a coherent source/manifest/lock combination. Do not revert only one package or treat this as on-chain rollback. D26, Gate0, B0, and complete original journeys remain open.
