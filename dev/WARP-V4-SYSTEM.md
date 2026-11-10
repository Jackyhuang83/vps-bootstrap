# WARP IPv4 system egress (isolated DEV prototype)

**Scope:** IPv6-only Debian/Ubuntu systemd VPS. Reuses the already working Cloudflare WARP **Local Proxy SOCKS5** on `127.0.0.1:40000`; independent sing-box TUN forwards **IPv4 TCP**. Original IPv6 default route, WARP proxy mode, proxy inbounds, SSH and existing sing-box services are not modified.

**Not production-ready:** No live VPS test yet. IPv4 UDP (including DNS over UDP/QUIC) is **not supported** by this prototype; this does *not* constitute a full system dual-stack implementation. Do not enable where reliable IPv4 UDP or IPv4 DNS is required. No changes to main script or default menu.

## Safety design

- `precheck`: read-only checks for active native IPv6 HTTPS, WARP SOCKS5 IPv4 WARP trace, systemd, TUN and existing default routes.
- `trial`: verifies sing-box config before introducing an isolated service/TUN; arms a separate systemd rollback timer **before** starting the service; checks both address families and reverts on failure.
- Trial rollback after 120 seconds unless `confirm` passes both IPv4 and IPv6 tests. `confirm` explicitly makes the independent service persistent.
- `disable`: requires ownership marker and exact managed ExecStart, stops only its own service and removes only the default IPv4 route scoped to `vbw4tun`.
- Fails closed on existing IPv4 default route / existing TUN or managed directory conflicts. Does not overwrite existing route, daemon or WARP configuration.

## Development validation

```sh
bash -n dev/warp-v4-system.sh
bash dev/warp-v4-system.sh precheck
```

Do **not** run `trial` on the production JP IPv6-only host until an independent review and throwaway VPS TUN test have passed. When authorized, `trial` and `confirm` are separate explicit operations and the watchdog rollback should be deliberately tested (including an unconfirmed run).

## Remaining acceptance tests

1. Syntax and candidate configuration validation on deployed sing-box 1.13+/1.14+.
2. IPv6-only disposable VPS trial: IPv4 TCP 200 + WARP trace, native IPv6 HTTPS, no SSH interruption.
3. Deliberate unconfirmed timeout rolls back to absent IPv4 default and healthy original WARP SOCKS5.
4. Confirm persists across service restart and host reboot; disable leaves IPv6 and existing services unchanged.
5. Investigate IPv4 UDP/DNS handling separately before labelling this a **complete IPv4 system exit**.
