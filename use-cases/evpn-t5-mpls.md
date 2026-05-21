# Use Case: EVPN-T5-MPLS

This use case configures and validates an MPLS backbone with OSPF, LDP, and an EVPN service across the PE triangle (R1, R2, R3).

> All configuration is applied by Claude via the Junos MCP server. No CLI interaction required.

**Prerequisites:** the infrastructure from the [main README](../README.md) must be up and running (containers started, NETCONF enabled, MCP server active, Claude Code connected).

---

## Scenario

```
              +----------+
              |   R11    |
              |   CE     |
              +--+----+--+
                eth1  eth2
                 |      |
                eth3  eth3
                 |      |
    +------------+--+  +--+------------+
    |      R1       |  |      R2       |
    |      PE       |  |      PE       |
    +--+----------+-+  +-+----------+--+
      eth2        eth1    eth1       eth2
                    \      /
                     \    /
                   (10.1.12.0/30)
        \                                /
       eth2                            eth2
          \                            /
        +--+----------------------------+--+
        |               R3                 |
        |               PE                 |
        +----------------+-----------------+
                        eth3
                         |
                    +----+----+
                    |   R12   |
                    |   CE    |
                    +---------+
```

> R11 is connected to R1 **and** R2 via two distinct L3 networks (no LACP aggregation): 192.168.111.0/24 toward R1, 192.168.112.0/24 toward R2.

### Interface mapping

> **cRPD naming:** cRPD exposes Linux interface names directly in Junos. Use `eth0`–`eth3` — **not** `et-0/0/x`.

| Router | eth0       | eth1           | eth2           | eth3                        |
|--------|-----------|----------------|----------------|-----------------------------|
| R1     | management | PE-PE ↔ R2     | PE-PE ↔ R3     | PE-CE ↔ R11 (192.168.111.x) |
| R2     | management | PE-PE ↔ R1     | PE-PE ↔ R3     | PE-CE ↔ R11 (192.168.112.x) |
| R3     | management | PE-PE ↔ R1     | PE-PE ↔ R2     | PE-CE ↔ R12 (192.168.12.x)  |
| R11    | management | PE-CE ↔ R1     | PE-CE ↔ R2     | —                           |
| R12    | management | PE-CE ↔ R3     | —              | —                           |

> **eth0 (management):** skip — do not configure routing IPs on this interface.

### Addressing plan

| Link              | Junos interface | Subnet            | Local IP         | Remote IP        | Remote router |
|-------------------|----------------|-------------------|------------------|------------------|---------------|
| R1 lo0.0 (underlay) | lo0.0        | 10.0.0.1/32       | —                | —                | —             |
| R2 lo0.0 (underlay) | lo0.0        | 10.0.0.2/32       | —                | —                | —             |
| R3 lo0.0 (underlay) | lo0.0        | 10.0.0.3/32       | —                | —                | —             |
| R1 lo0.1 (T5-VRF)   | lo0.1        | 10.0.1.1/32       | —                | —                | —             |
| R2 lo0.1 (T5-VRF)   | lo0.1        | 10.0.1.2/32       | —                | —                | —             |
| R3 lo0.1 (T5-VRF)   | lo0.1        | 10.0.1.3/32       | —                | —                | —             |
| R11 lo0.0           | lo0.0        | 10.0.1.11/32      | —                | —                | —             |
| R12 lo0.0           | lo0.0        | 10.0.1.12/32      | —                | —                | —             |
| R1 ↔ R2           | R1: eth1       | 10.1.12.0/30      | 10.1.12.1        | 10.1.12.2        | R2            |
| R1 ↔ R3           | R1: eth2       | 10.1.13.0/30      | 10.1.13.1        | 10.1.13.2        | R3            |
| R2 ↔ R1           | R2: eth1       | 10.1.12.0/30      | 10.1.12.2        | 10.1.12.1        | R1            |
| R2 ↔ R3           | R2: eth2       | 10.1.23.0/30      | 10.1.23.1        | 10.1.23.2        | R3            |
| R3 ↔ R1           | R3: eth1       | 10.1.13.0/30      | 10.1.13.2        | 10.1.13.1        | R1            |
| R3 ↔ R2           | R3: eth2       | 10.1.23.0/30      | 10.1.23.2        | 10.1.23.1        | R2            |
| R1 ↔ R11          | R1: eth3       | 192.168.111.0/24  | 192.168.111.1    | 192.168.111.11   | R11           |
| R2 ↔ R11          | R2: eth3       | 192.168.112.0/24  | 192.168.112.2    | 192.168.112.11   | R11           |
| R3 ↔ R12          | R3: eth3       | 192.168.12.0/24   | 192.168.12.3     | 192.168.12.12    | R12           |

### Protocols

| Layer   | Protocol     | Role                                                      |
|---------|--------------|-----------------------------------------------------------|
| IGP     | OSPF area 0  | Reachability between PE loopbacks                         |
| MPLS    | LDP          | Label distribution on PE-PE links                         |
| Overlay | iBGP EVPN    | Full mesh between PEs (family evpn + family inet unicast) |
| PE-CE   | eBGP         | R11 (AS 65011) and R12 (AS 65012) toward PEs (AS 65000)  |

---

## Step 1 — Configure interfaces and loopbacks

**Prompt to Claude:**
```
Configure interfaces and loopbacks on R1, R2 and R3 using the following addressing plan.
Do not configure anything on eth0 (management interface).
Use eth1 and eth2 as the PE-PE interface names (cRPD uses Linux interface names directly in Junos).

R1:
  lo0.0   10.0.0.1/32
  eth1    10.1.12.1/30   (link to R2)
  eth2    10.1.13.1/30   (link to R3)

R2:
  lo0.0   10.0.0.2/32
  eth1    10.1.12.2/30   (link to R1)
  eth2    10.1.23.1/30   (link to R3)

R3:
  lo0.0   10.0.0.3/32
  eth1    10.1.13.2/30   (link to R1)
  eth2    10.1.23.2/30   (link to R2)

Also configure lo0.0 on R11 and R12 (CE loopback, advertised via eBGP in Step 6):
  R11: lo0.0   10.0.1.11/32
  R12: lo0.0   10.0.1.12/32
```

---

## Step 2 — Configure OSPF area 0

OSPF provides IGP reachability between PE loopbacks. All PE-PE interfaces and loopbacks are included in area 0.

> **cRPD interface naming in protocol stanzas:** unlike classic Junos where logical interfaces are referenced with their unit suffix (`eth1.0`), cRPD tracks Linux interfaces internally without the unit suffix. Use `eth1` and `eth2` (not `eth1.0` / `eth2.0`) everywhere in `protocols ospf`, `protocols ldp`, etc. The loopback is an exception: use `lo0.0` as usual.

**Prompt to Claude:**
```
Configure OSPF area 0 on R1, R2 and R3.
Include eth1 and eth2 as active interfaces (interface-type p2p, no unit suffix — cRPD requirement).
Include lo0.0 as a passive interface.
```

**Verify:**
```
Show OSPF neighbors on R1, R2 and R3.
Expected: each PE has 2 OSPF adjacencies (full mesh).
```

---

## Step 3 — Configure LDP

LDP distributes MPLS labels over the PE-PE links established by OSPF.

> **cRPD requirements:**
> - Enable `family mpls` under each PE-PE interface unit (`set interfaces eth1 unit 0 family mpls`) — required for MPLS label forwarding.
> - Reference interfaces **without unit suffix** in `protocols ldp` (same rule as OSPF): use `eth1`, `eth2`, not `eth1.0`, `eth2.0`.

**Prompt to Claude:**
```
Enable LDP on R1, R2 and R3.
First enable family mpls on eth1 and eth2 (set interfaces eth1 unit 0 family mpls, same for eth2).
Activate LDP on eth1 and eth2 (no unit suffix — cRPD requirement).
Also activate LDP on lo0.0 and use it as the LDP router-id.
```

**Verify:**
```
Show LDP neighbors on R1, R2 and R3.
Expected: each PE has 2 LDP sessions up (full mesh).
```

---

## Step 4 — Configure iBGP EVPN full mesh

An iBGP full mesh with address-family `evpn` is established between PE loopbacks.

> **cRPD requirements:**
> - Set `routing-options router-id` to the loopback address — required for LDP router-id resolution.
> - Set `routing-options autonomous-system 65000` — required for BGP.
> - Enable `family inet unicast` in the BGP group alongside `family evpn` — required for BGP to resolve EVPN next-hops via `inet.3` (LDP labels).
> - Enable `protocols mpls` on the PE-PE interfaces (`eth1`, `eth2`) — required for EVPN type-5 MPLS forwarding.

**Prompt to Claude:**
```
Configure iBGP EVPN on R1, R2 and R3.
Use the following loopback addresses as BGP peer IPs:
  R1: 10.0.0.1
  R2: 10.0.0.2
  R3: 10.0.0.3
Full mesh (no route reflector). Local AS 65000 on all PEs.
Enable address-family evpn and family inet unicast on all sessions.
Set routing-options router-id to the loopback address and autonomous-system 65000.
Enable protocols mpls on eth1 and eth2 (PE-PE interfaces).
```

**Verify:**
```
Show BGP summary on R1, R2 and R3.
Expected: 2 established iBGP sessions per PE, tables bgp.evpn.0 and inet.0 visible.
```

---

## Step 5 — Configure EVPN T5-VRF (type 5 — IP Prefix routes)

This step configures an L3VPN-style EVPN service using **route type 5 (IP Prefix)**. Each PE gets a VRF routing instance (`T5-VRF`) that advertises IP prefixes over the EVPN control plane with MPLS encapsulation.

R11 is connected to R1 and R2 via **two separate L3 subnets** (no aggregation, no ESI). R12 is single-homed to R3.

> **cRPD limitation:** ESI multi-homing is not configurable on `eth` interfaces in cRPD (requires ae/aggregated-ethernet). MAC-VRF with MPLS encapsulation is also not supported. This scenario uses pure L3 EVPN type-5 (T5-VRF) with plain `family inet` on the CE-facing interfaces.

> **cRPD requirements for routing-instances:**
> - Reference CE-facing interfaces **without unit suffix** in the routing-instance: use `eth3`, not `eth3.0` (same rule as OSPF/LDP).
> - `encapsulation mpls` is the default for `ip-prefix-routes` and need not be specified explicitly.
> - `advertise direct-nexthop` alone does **not** export /32 prefixes (loopbacks, CE host routes) as EVPN type-5. An explicit `export` policy covering `direct` and `bgp` protocols must be applied under `ip-prefix-routes`.

**Prompt to Claude:**
```
Configure EVPN type-5 VRF (T5-VRF) on R1, R2 and R3.

=== PE-CE interfaces (family inet) ===
  R1 eth3: 192.168.111.1/24  (link to R11)
  R2 eth3: 192.168.112.2/24  (link to R11)
  R3 eth3: 192.168.12.3/24   (link to R12)

=== PE loopbacks in VRF (lo0.1 — configured at this step) ===
  R1 lo0.1: 10.0.1.1/32
  R2 lo0.1: 10.0.1.2/32
  R3 lo0.1: 10.0.1.3/32

=== T5-VRF — IP prefix VRF (all PEs) ===
Routing instance name: T5-VRF, instance-type vrf.
Route-distinguisher: <loopback>:100
  R1: 10.0.0.1:100  R2: 10.0.0.2:100  R3: 10.0.0.3:100
VRF target: target:65000:100 (import and export).
vrf-table-label (required for MPLS forwarding).
EVPN ip-prefix-routes: advertise direct-nexthop.
Interfaces in T5-VRF:
  R1: eth3 (no unit suffix — cRPD rule), lo0.1 (loopback keeps unit suffix)
  R2: eth3, lo0.1
  R3: eth3, lo0.1

=== EVPN export policy (required for /32 advertisement) ===
Create policy EVPN-T5-EXPORT on all PEs:
  term 1: from protocol direct → accept
  term 2: from protocol bgp → accept
Apply: set routing-instances T5-VRF protocols evpn ip-prefix-routes export EVPN-T5-EXPORT

Show the diff and wait for confirmation before committing.
```

---

## Step 6 — Configure eBGP PE-CE

An eBGP session is established between each CE and its connected PE(s). CEs advertise all their direct routes (including lo0.1) into the VRF. The PE redistributes those routes as EVPN type-5 prefixes.

| CE  | AS    | PE  | PE AS | Link subnet       |
|-----|-------|-----|-------|-------------------|
| R11 | 65011 | R1  | 65000 | 192.168.111.0/24  |
| R11 | 65011 | R2  | 65000 | 192.168.112.0/24  |
| R12 | 65012 | R3  | 65000 | 192.168.12.0/24   |

**Prompt to Claude:**
```
Configure eBGP PE-CE sessions.

=== On R1 (in routing-instance T5-VRF) ===
BGP group CE-R11, type external, peer-as 65011.
Neighbor 192.168.111.11.
Export policy EXPORT-TO-CE: advertise direct + bgp + evpn routes from T5-VRF.
  term 1: from protocol direct → accept
  term 2: from protocol bgp → accept
  term 3: from protocol evpn → accept   ← required to redistribute EVPN-learned routes to CE

=== On R2 (in routing-instance T5-VRF) ===
BGP group CE-R11, type external, peer-as 65011.
Neighbor 192.168.112.11.
Export policy EXPORT-TO-CE (same 3 terms as R1).

=== On R3 (in routing-instance T5-VRF) ===
BGP group CE-R12, type external, peer-as 65012.
Neighbor 192.168.12.12.
Export policy EXPORT-TO-CE (same 3 terms).

=== On R11 (global routing table) ===
BGP group PE-R1, type external, local-as 65011, peer-as 65000, neighbor 192.168.111.1.
BGP group PE-R2, type external, local-as 65011, peer-as 65000, neighbor 192.168.112.2.
Export policy: advertise all direct routes.

=== On R12 (global routing table) ===
BGP group PE-R3, type external, local-as 65012, peer-as 65000, neighbor 192.168.12.3.
Export policy: advertise all direct routes.

Show the diff and wait for confirmation before committing.
```

**Verify:**
```
Show BGP summary on R1, R2, R3, R11 and R12.
Expected: eBGP sessions Established between each CE and its PE(s).
Show route table T5-VRF.inet.0 on R1 — expected: CE routes (10.0.1.11/32 from R11 lo0.0, 192.168.111.0/24, 192.168.112.0/24) visible.
```

---

## Step 7 — Verify end-to-end

**Prompt to Claude:**
```
Verify the EVPN type-5 deployment end-to-end on R1, R2, R3, R11 and R12.

=== PE side ===
- Show BGP summary on R1, R2, R3 — expected: iBGP EVPN sessions + eBGP CE sessions all Established.
- Show VRF routing table on each PE (show route table T5-VRF.inet.0) —
  expected: lo0.1 of all PEs (10.0.1.1/32, 10.0.1.2/32, 10.0.1.3/32),
  CE subnets (192.168.111.0/24, 192.168.112.0/24, 192.168.12.0/24),
  and CE loopbacks (10.0.1.11/32, 10.0.1.12/32) learned via eBGP.
- Show EVPN type-5 prefixes advertised to peers (show route advertising-protocol bgp <peer>).
- Show MPLS label bindings (show route table mpls.0).

=== CE side ===
- Show BGP summary on R11 and R12 — expected: eBGP sessions Established.
- Show route table on R11 — expected (learned via eBGP from R1 and R2, dual-homed):
  PE lo0.1: 10.0.1.1/32, 10.0.1.2/32, 10.0.1.3/32
  Remote CE loopback: 10.0.1.12/32 (AS path: 65000 65012)
  Remote CE subnet: 192.168.12.0/24
- Show route table on R12 — expected (learned via eBGP from R3):
  PE lo0.1: 10.0.1.1/32, 10.0.1.2/32, 10.0.1.3/32
  Remote CE loopback: 10.0.1.11/32 (AS path: 65000 65011)
  Remote CE subnets: 192.168.111.0/24, 192.168.112.0/24
```

---

## Rollback

To reset all routers to base configuration and start fresh:

**Prompt to Claude:**
```
Reset R1, R2, R3, R11 and R12 to a clean base configuration.
Keep only:
  - system host-name
  - system root-authentication
  - system services netconf ssh
  - system services ssh root-login allow   ← required for NETCONF password auth on port 830
Remove everything else (interfaces, protocols, routing-options, routing-instances, policy-options).
Show the diff before committing and wait for confirmation.
```
