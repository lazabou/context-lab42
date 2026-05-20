# Use Case: EVPN-MPLS

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
            eth1  eth2  (LACP bond toward R1 and R2)
             |      |
            eth3  eth3
             |      |
      +------+--+  +--+------+
      |   R1    +--+   R2    |
      |   PE    |eth1  eth1  |   PE    |
      +----+----+  +----+----+
          eth2          eth2
            \              /
             \            /
           +--+----------+--+
           |       R3       |
           |       PE       |
           +-------+--------+
                   |eth3
                   |
              +----+----+
              |   R12   |
              |   CE    |
              +---------+
```

### Interface mapping

> **cRPD naming:** cRPD exposes Linux interface names directly in Junos. Use `eth0`–`eth3` — **not** `et-0/0/x`.

| Router | eth0       | eth1           | eth2           | eth3             |
|--------|-----------|----------------|----------------|------------------|
| R1     | management | PE-PE ↔ R2     | PE-PE ↔ R3     | PE-CE ↔ R11      |
| R2     | management | PE-PE ↔ R1     | PE-PE ↔ R3     | PE-CE ↔ R11      |
| R3     | management | PE-PE ↔ R1     | PE-PE ↔ R2     | PE-CE ↔ R12      |
| R11    | management | PE-CE ↔ R1     | PE-CE ↔ R2     | —                |
| R12    | management | PE-CE ↔ R3     | —              | —                |

> **eth0 (management):** skip — do not configure routing IPs on this interface.

### Addressing plan

| Link              | Junos interface | Subnet           | Local IP        | Remote IP       | Remote router       |
|-------------------|----------------|------------------|-----------------|-----------------|---------------------|
| R1 lo0            | lo0.0          | 10.0.0.1/32      | —               | —               | —                   |
| R2 lo0            | lo0.0          | 10.0.0.2/32      | —               | —               | —                   |
| R3 lo0            | lo0.0          | 10.0.0.3/32      | —               | —               | —                   |
| R1 ↔ R2           | R1: eth1       | 10.1.12.0/30     | 10.1.12.1       | 10.1.12.2       | R2                  |
| R1 ↔ R3           | R1: eth2       | 10.1.13.0/30     | 10.1.13.1       | 10.1.13.2       | R3                  |
| R2 ↔ R1           | R2: eth1       | 10.1.12.0/30     | 10.1.12.2       | 10.1.12.1       | R1                  |
| R2 ↔ R3           | R2: eth2       | 10.1.23.0/30     | 10.1.23.1       | 10.1.23.2       | R3                  |
| R3 ↔ R1           | R3: eth1       | 10.1.13.0/30     | 10.1.13.2       | 10.1.13.1       | R1                  |
| R3 ↔ R2           | R3: eth2       | 10.1.23.0/30     | 10.1.23.2       | 10.1.23.1       | R2                  |
| R1 ↔ R11          | R1: eth3       | 192.168.11.0/24  | 192.168.11.1    | 192.168.11.11   | R11 (multi-homed)   |
| R2 ↔ R11          | R2: eth3       | 192.168.11.0/24  | 192.168.11.2    | 192.168.11.11   | R11 (multi-homed)   |
| VGA R11 segment   | —              | 192.168.11.0/24  | 192.168.11.254  | —               | Anycast GW (R1+R2)  |
| R3 ↔ R12          | R3: eth3       | 192.168.12.0/24  | 192.168.12.3    | 192.168.12.12   | R12                 |

### Protocols

| Layer   | Protocol     | Role                                        |
|---------|--------------|---------------------------------------------|
| IGP     | OSPF area 0  | Reachability between PE loopbacks           |
| MPLS    | LDP          | Label distribution on PE-PE links           |
| Overlay | iBGP EVPN    | Full mesh between PEs (address-family evpn) |
| PE-CE   | EVPN         | R11 and R12 as EVPN CE                      |

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

**Prompt to Claude:**
```
Configure iBGP EVPN on R1, R2 and R3.
Use the following loopback addresses as BGP peer IPs:
  R1: 10.0.0.1
  R2: 10.0.0.2
  R3: 10.0.0.3
Full mesh (no route reflector). Local AS 65000 on all PEs.
Enable address-family evpn on all sessions.
```

**Verify:**
```
Show BGP summary on R1, R2 and R3.
Expected: 2 established iBGP sessions per PE.
```

---

## Step 5 — Configure EVPN VRF (type 5 — IP Prefix routes)

This step configures an L3VPN-style EVPN service using **route type 5 (IP Prefix)**. Each PE gets a VRF routing instance (`T5-VRF`) that advertises IP prefixes over the EVPN control plane with MPLS encapsulation.

R11 is **multi-homed in all-active mode** to R1 and R2 via LACP with a shared ESI. R12 is single-homed to R3.

**Prompt to Claude:**
```
Configure EVPN type-5 VRF on R1, R2 and R3.

=== VRF (all PEs) ===
Routing instance name: T5-VRF, instance-type vrf.
Route-distinguisher: <loopback>:100 (10.0.0.1:100 / 10.0.0.2:100 / 10.0.0.3:100).
VRF target: target:65000:100 (import and export).
EVPN: ip-prefix-routes, MPLS encapsulation.

=== R11 — multi-homed all-active to R1 and R2 ===
ESI on R1 eth3 and R2 eth3:
  esi 00:00:00:00:00:00:00:00:00:11
  all-active mode
  LACP system-id 00:00:00:00:00:11

R1 eth3: family inet address 192.168.11.1/24 — add to T5-VRF
R2 eth3: family inet address 192.168.11.2/24 — add to T5-VRF
Virtual Gateway Address (anycast): 192.168.11.254/24 on R1 and R2 (same IP, same MAC)

=== R12 — single-homed to R3 ===
R3 eth3: family inet address 192.168.12.3/24 — add to T5-VRF

Show the diff and wait for confirmation before committing.
```

---

## Step 6 — Verify end-to-end

**Prompt to Claude:**
```
Verify the EVPN type-5 deployment end-to-end on R1, R2 and R3:
- Show routing instance summary (show route instance VRF-EVPN)
- Show EVPN type-5 prefixes in BGP (show bgp neighbor 10.0.0.x advertised-routes)
- Show the VRF routing table (show route table VRF-EVPN.inet.0)
- Show MPLS label bindings (show route table mpls.0)
```

---

## Rollback

To reset all routers to base configuration (hostname + root password only) and start fresh:

**Prompt to Claude:**
```
Reset R1, R2, R3, R11 and R12 to a clean base configuration.
Keep only system host-name and root-authentication. Remove everything else.
Show the diff before committing and wait for confirmation.
```
