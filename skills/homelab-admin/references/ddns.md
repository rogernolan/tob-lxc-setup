# Gateway Cloudflare DDNS

Run on the verified gateway LXC. The repo integrates with an existing deployment at:

- `/etc/cloudflare-ddns/cloudflare-ddns.env`
- `/usr/local/sbin/cloudflare-ddns`
- `CF_ALIASES`, a whitespace-separated hostname list in that environment file.

It contains **no installer or standalone DDNS alias command**. Do not invent one or create a Caddy site just to add DNS.

## Choose the requested operation

If the request includes publishing an HTTP(S) service, use [services.md](services.md) and `add-caddy-host --update-dns`, which adds the hostname to the existing aliases. That option currently accepts only lowercase subdomains of `hatbat.net`.

For DDNS alone, inspect the existing updater's behavior and scheduler, then edit the alias list directly. For a first DDNS installation, discover whether an updater is present and establish zone, names, A/AAAA behavior, WAN-IP detection, proxy setting, scoped credentials and schedule. Prepare the concrete configuration/service before any needed user decision; do not assume a provider package, timer name or updater interface. Installing missing DDNS is separate work from the repo's Caddy helper.

## Extend existing aliases

Verify gateway identity, root ownership/permissions of the environment/updater, updater configuration schema and existing timer/cron/service. Inspect code and unit configuration with secret redaction; do not dump the environment file, process environment or secret-bearing logs. Extract only `CF_ALIASES` and other known non-secret fields. Do not source an untrusted file as root merely to inspect it.

Check desired hostname and existing DNS record/type/target for conflicts. Preserve the current DDNS base hostname, every other alias, credential, proxy setting and update schedule. Before mutation, retain a root-only backup and the non-secret before-state of affected DNS records.

Stage a root-owned `0600` candidate beside the environment file, appending the requested alias once. Preserve the file's remaining content. Validate shell syntax and the updater's actual schema, then atomically replace the environment file. Avoid racing a Caddy alias update or scheduled updater; inspect how the installed updater serializes operations before choosing an execution window/lock.

Run the existing updater using its verified interface. When it matches the repo's expected no-argument command:

```sh
sudo /usr/local/sbin/cloudflare-ddns
```

Verify updater success, the authoritative record, the intended A/AAAA behavior and continued scheduling. Recursive resolution may lag TTLs; Cloudflare-proxied DNS may return proxy addresses, so verify the configured origin through provider state rather than equating a public answer with the WAN IP.

If update fails, restore the prior local environment when appropriate and inspect affected remote DNS records. An updater can succeed for one record and fail for another; restoring the local file does not undo provider changes. Reconcile only records changed by this operation against captured before-state, preserving concurrent changes. Stop repeated mutations when the cause or current state is unclear, and report local/remote status separately. Never print or put the API token in command arguments or repository files.
