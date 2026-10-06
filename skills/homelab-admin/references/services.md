# Publish a service behind the gateway

Run Caddy operations on the verified gateway LXC. Read the repo's `scripts/add-caddy-host`, `scripts/install-caddy-host` and README. Establish hostname, intended audience/authentication, verified guest address, listening port and HTTP versus HTTPS upstream. Installing the app itself is separate work unless included in the request.

## Prerequisites

Confirm working Caddy/systemd and `/etc/caddy/Caddyfile` containing `import /etc/caddy/sites-enabled/*.caddy`. Inspect existing matching site content and DNS. Probe the service **from the gateway**, because a working LAN connection does not establish gateway reachability. If the guest firewall needs an allowance, use [firewall.md](firewall.md), preserving its full current policy.

The helper accepts lowercase DNS names and `http://` or `https://` RFC1918 IPv4 upstreams with an explicit port. It rejects paths, queries, fragments, credentials, IPv6 and upstream hostnames. Do not silently alter an unsupported target; resolve its required routing/configuration first.

DNS changes only with `--update-dns`. For DNS already resolving correctly, omit it. For a requested new DDNS alias plus service, confirm the deployment described in [ddns.md](ddns.md) exists and use the flag. Missing DDNS prerequisites require configuring them before publication, not bypassing the failure. Publishing exposes a service via the existing gateway; preserve existing access controls and resolve an unspecified audience when it materially affects security.

## Install then invoke

Prefer the installed command when its source/version matches reviewed code. Otherwise stage the installer and payload from the same reviewed checkout on the gateway, inspect both, and use the exact payload:

```sh
sudo sh /path/to/reviewed/scripts/install-caddy-host \
  --payload-file /path/to/reviewed/scripts/add-caddy-host -- \
  --update-dns notes.hatbat.net http://192.168.68.90:8080
```

This installs `/usr/local/sbin/add-caddy-host` **and immediately invokes it** with the forwarded arguments; it is not an install-only preview. The example hostname/IP/port are illustrative. There is no dry-run option. Prepare the exact invocation and inspect required/current configuration before running it.

For subsequent operations:

```sh
sudo add-caddy-host --update-dns notes.hatbat.net http://192.168.68.90:8080
```

Supply `--force` only when replacement of an inspected, differing site is authorized; retain any existing authentication/header/route directives rather than accidentally replacing them with a simple proxy. Use `--insecure-upstream-tls` only when Rog explicitly accepts skipping certificate verification for that HTTPS upstream. The helper does not support a custom CA flag. Direct execution of reviewed `add-caddy-host` is a fallback for temporary operation/recovery; it does not update the installed command.

## Verify and recover

The helper probes the upstream, uses `flock`, backs up local files under root-only `/var/backups/caddy-hosts/`, writes `/etc/caddy/sites-enabled/HOSTNAME.caddy`, validates and reloads Caddy, and optionally updates `CF_ALIASES`/Cloudflare DNS. Identical site content is accepted; differing content requires explicit replacement.

Check the resulting site, Caddy validation/service state, DNS, local HTTPS with the hostname/SNI directed to `127.0.0.1`, certificate state and a fresh client request through the intended route. A returned HTTP error can establish connectivity while failing the application workflow. Test the requested service behavior and expected authentication as well as TLS.

The final local HTTPS check can exhaust retries and still return exit 0 with a message that TLS is not ready. That result means configuration is active and HTTPS verification remains pending; inspect certificate logs and perform a bounded follow-up check rather than claiming success or rerunning mutations. A local `--resolve` check also does not prove public DNS or external gateway reachability.

Validation, DNS-update and reload failures attempt **local** rollback. Cloudflare may already have changed, and rollback reload is best-effort. Verify actual Caddy/site/environment and affected provider records; do not promise that every component was restored. Restore from the operation's backup only within the authorized scope, preserving concurrent changes, and report any unresolved state.
