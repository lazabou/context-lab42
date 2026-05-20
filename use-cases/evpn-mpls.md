# Use Case: EVPN-MPLS

This use case configures and validates an MPLS backbone with OSPF, LDP, and an EVPN service across the PE triangle (R1, R2, R3).

> All configuration is applied by Claude via the Junos MCP server. No CLI interaction required.

**Prerequisites:** the infrastructure from the [main README](../README.md) must be up and running (containers started, NETCONF enabled, MCP server active, Claude Code connected).

---

## Scenario

```
        +------+          +------+
        |  R11 |          |  R12 |
        |  CE  |          |  CE  |
        +--+---+          +---+--+
           |                  |
        et-0/0/1           et-0/0/1
           |                  |
     +-----+----+        +----+-----+
     |    R1    +--------+    R2    |
     |    PE    | et-0/0/1  |    PE    |
     +-----+----+        +----+-----+
           \  et-0/0/2  et-0/0/2  /
            \                /
             \              /
           +--+------------+--+
           |        R3        |
           |        PE        |
           +------------------+
```

### Interface mapping

> **cRPD naming:** cRPD exposes Linux interface names directly in Junos. Use `eth0`, `eth1`, `eth2` — **not** `et-0/0/0`, `et-0/0/1`, `et-0/0/2`.

| Docker interface | Junos interface | Connected to |
|-----------------|-----------------|--------------|
| eth0            | eth0            | `lab` network (management) — **skip, do not configure routing IPs** |
| eth1            | eth1            | PE-PE or PE-CE link (see table below) |
| eth2            | eth2            | PE-PE link (PEs only) |

### Addressing plan

| Link      | Junos interface | Subnet        | Local IP   | Remote IP  | Remote router |
|-----------|----------------|---------------|------------|------------|---------------|
| R1 lo0    | lo0.0          | 10.0.0.1/32   | —          | —          | —             |
| R2 lo0    | lo0.0          | 10.0.0.2/32   | —          | —          | —             |
| R3 lo0    | lo0.0          | 10.0.0.3/32   | —          | —          | —             |
| R1 ↔ R2  | R1: eth1       | 10.1.12.0/30  | 10.1.12.1  | 10.1.12.2  | R2            |
| R1 ↔ R3  | R1: eth2       | 10.1.13.0/30  | 10.1.13.1  | 10.1.13.2  | R3            |
| R2 ↔ R1  | R2: eth1       | 10.1.12.0/30  | 10.1.12.2  | 10.1.12.1  | R1            |
| R2 ↔ R3  | R2: eth2       | 10.1.23.0/30  | 10.1.23.1  | 10.1.23.2  | R3            |
| R3 ↔ R1  | R3: eth1       | 10.1.13.0/30  | 10.1.13.2  | 10.1.13.1  | R1            |
| R3 ↔ R2  | R3: eth2       | 10.1.23.0/30  | 10.1.23.2  | 10.1.23.1  | R2            |
| R2 ↔ R11 | —              | 10.1.211.0/30 | 10.1.211.1 | 10.1.211.2 | R11           |
| R3 ↔ R12 | —              | 10.1.312.0/30 | 10.1.312.1 | 10.1.312.2 | R12           |

> **Note on CE links:** in this lab, R11 and R12 are on the `lab` management bridge (eth0). A dedicated PE-CE physical link on eth1/et-0/0/1 is only available on routers that are not already using that interface for a PE-PE link. Adjust accordingly if you rewire the topology.

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

## Step 5 — Configure EVPN service

Define the EVPN instance and bind the CE-facing interfaces.

**Prompt to Claude:**
```
Configure an EVPN instance (EVI 100) on R1, R2 and R3.
Use route-distinguisher <loopback>:100 and route-target 65000:100 (import and export).
Bind the CE-facing interface on each PE to the EVI.
R1 and R2 connect to R11; R3 connects to R12.
```

---

## Step 6 — Verify end-to-end

**Prompt to Claude:**
```
Verify the EVPN-MPLS deployment end-to-end on R1, R2 and R3:
- Show EVPN instance summary
- Show BGP EVPN routes (show bgp evpn)
- Show MPLS forwarding table (show mpls forwarding)
- Show MAC table for EVI 100
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
