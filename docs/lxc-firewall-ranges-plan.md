# Application protocol and range support

Extend the approved application profile without changing other profiles:
`--port PORT|START-END` stays TCP; `--udp-port PORT|START-END` selects UDP.
Either option can be repeated, including UDP-only applications. Validate decimal
endpoints 1-65535, reject reversed/malformed ranges, normalize leading zeros and
equal endpoints, deduplicate exact normalized entries, and sort by endpoints.
Overlapping ranges remain separate equivalent allow rules. Render Proxmox range
syntax START:END. Keep SSH, discovery, source scoping and transactional safety.
No guest IDs or Bambuddy-specific port lists belong in executable code.

- [x] Add failing CLI tests for ranges, UDP, validation and source scoping.
- [x] Implement parser and protocol-specific deterministic rendering.
- [x] Verify native range compilation on Proxmox and run local regression suites.
- [x] Document Bambuddy preview, update installer pin, publish a separate PR.

Live tests on 105 and Bambuddy require a later attended session; this work does
not apply policies or modify guest services while Rog is away.

Verification: CLI suite passed on macOS Bash and Proxmox Bash; native compiler
passed 38 assertions. Installer suite, 34 transaction assertions and six target
assertions passed. Shell syntax and diff whitespace checks passed. Regression
tests were observed failing before implementation. No live policy was changed.
