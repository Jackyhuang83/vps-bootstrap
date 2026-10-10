# Dev8 network tuning validation

Status: NOT validated on a real VPS or real streaming/chat clients.
Stable v1.9.0 is untouched. No persistent HTB installation exists.

## Kernel integration (automated)

The test file tests/network-htb-veth-integration.sh may be run as root in a
disposable Linux VM with iproute2, jq and CAP_NET_ADMIN. It creates one
unrouted, unaddressed veth pair. It applies real fq_codel/HTB in the kernel
only to that pair; other interfaces, traffic routes and host sysctl are not
changed. The device is deleted on exit.

Tests: actual HTB-to-fq_codel restoration using the same source-extracted
recovery worker as Dev7, refusal after third-party qdisc substitution, and
recovery after SIGKILL of the launching shell via an independent process.
A CAP_NET_ADMIN failure logs SKIP and does NOT establish kernel validation.
This alone does NOT prove that systemd timers, reboot, SSH loss, Cloud VPS
NIC drivers, v4/v6 routing, or live applications are safe.

## Disposable cloud VPS gate (NOT PERFORMED)

1. Use a TEST VPS with a functioning service-provider web console or
   rescue access, never the only production ingress/egress VPS.
2. Record kernel, Linux distribution, eth/veth driver, netmask, default routes,
   initial qdisc and proxy services. Confirm console-based SSH recovery.
3. Do not touch existing fq, mq, clsact, ingress, HTB, NetworkManager-owned
   or other external qdisc configurations.
4. Confirm original fq_codel options can be reconstructed and 60-second
   independent systemd timer exists BEFORE applying any HTB.
5. Only if dev5 has six valid samples AND dev4 confirms a conservative knee,
   opt in to Dev7 experimental 60-second test using TRIAL confirmation.
6. Independently verify both IPv4 and IPv6 availability, SSH continuity,
   qdisc restoration, service status and whether video playback survived.
7. Perform separate controlled process kill and VM reboot tests, using the
   provider console. A systemd timer is NOT reboot-persistent by design.
   Any unsafe result must block release.
8. Validate the 10, 20, 30, 100, 200, 300 and 500 Mbps plan tiers as suitable.
   Inadequate samples or any regressed chat/video/web -> retain baseline.

## Real client A/B observations (NOT PERFORMED)

Use the same video/live channel and resolution, same client device, same web
pages and chat peer. Baseline versus 60-second HTB trial should be assessed
with comparable traffic/time-of-day. Important: the Dev7 live HTB experiment
lasts only 60 seconds; the required >=300-second A/B observations CANNOT be
fully collected during that short trial. Therefore the read-only A/B gate is
currently for future, separately approved long-duration validation only,
NOT evidence that Dev7 has provided video improvements.

Synthetic JSON example (DEMONSTRATION ONLY, not real data):

    {
      "schema":1,
      "tier_mbps":30,
      "video_source":"same 1080p news stream",
      "video_resolution":"1080p",
      "samples":[
        {"phase":"baseline","round":1,"duration_s":360,"video_stalls":2,"video_buffer_s":15,"video_dropped_frames":0,"web_p95_ms":420,"chat_p95_ms":180,"ping_p95_ms":95,"loss_pct":0},
        {"phase":"trial","round":1,"duration_s":360,"video_stalls":0,"video_buffer_s":0,"video_dropped_frames":0,"web_p95_ms":345,"chat_p95_ms":175,"ping_p95_ms":83,"loss_pct":0},
        {"phase":"baseline","round":2,"duration_s":360,"video_stalls":1,"video_buffer_s":12,"video_dropped_frames":0,"web_p95_ms":405,"chat_p95_ms":185,"ping_p95_ms":98,"loss_pct":0},
        {"phase":"trial","round":2,"duration_s":360,"video_stalls":0,"video_buffer_s":0,"video_dropped_frames":0,"web_p95_ms":338,"chat_p95_ms":171,"ping_p95_ms":85,"loss_pct":0}
      ]
    }

video_stalls counts playback buffering events; video_buffer_s their duration;
dropped frames come from client statistics. web_p95_ms is p95 web loading
response time, chat_p95_ms a controlled roundtrip timing metric; ping_p95_ms
and loss_pct must use the same test endpoint. These are manual measurements,
not authenticated evidence.

Network tuning menu option 14 reviews an A/B JSON file READ-ONLY.
verdict=inconclusive means incomplete or invalid evidence;
verdict=keep_baseline means the evidence does not justify shaping;
verdict=candidate_for_further_field_validation means apparent improvement
in manually entered numbers; the live VPS has NOT been verified.
Every result explicitly sets auto_apply=false and field_verified=false.

Do not enable permanent shaping automatically, even for a positive verdict.
