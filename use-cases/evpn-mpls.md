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
        et-0/0/0           et-0/0/0
           |                  |
     +-----+----+        +----+-----+
     |    R1    +--------+    R2    |
     |    PE    |        |    PE    |
     +-----+----+        +----+-----+
           \                  /
            \                /
             \              /
           +--+------------+--+
           |        R3        |
           |        PE        |
           +------------------+
```

### Addressing plan

| Link         | Subnet          | R1 side       | R2/R3 side    |
|--------------|-----------------|---------------|---------------|
| R1 loopback  | 10.0.0.1/32     | —             | —             |
| R2 loopback  | 10.0.0.2/32     | —             | —             |
| R3 loopback  | 10.0.0.3/32     | —             | —             |
| R1 ↔ R2     | 10.1.12.0/30    | 10.1.12.1     | 10.1.12.2     |
| R1 ↔ R3     | 10.1.13.0/30    | 10.1.13.1     | 10.1.13.2     |
| R2 ↔ R3     | 10.1.23.0/30    | 10.1.23.1     | 10.1.23.2     |
| R1 ↔ R11    | 10.1.111.0/30   | 10.1.111.1    | 10.1.111.2    |
| R2 ↔ R11    | 10.1.211.0/30   | 10.1.211.1    | 10.1.211.2    |
| R3 ↔ R12    | 10.1.312.0/30   | 10.1.312.1    | 10.1.312.2    |

### Protocols

| Layer       | Protocol | Role                                      |
|-------------|----------|-------------------------------------------|
| IGP         | OSPF area 0 | Reachability between PE loopbacks      |
| MPLS        | LDP      | Label distribution on PE-PE links         |
| Overlay     | iBGP EVPN | Full mesh between PEs (address-family evpn) |
| PE-CE       | EVPN     | R11 and R12 as EVPN CE (bridged or routed) |

---

## Step 1 — Configure interfaces and loopbacks

Claude applies interface IPs and loopbacks on each PE via `load_and_commit_config`.

**Prompt to Claude:**
```
Configure interfaces and loopbacks on R1, R2 and R3 according to the EVPN-MPLS addressing plan.
Use the interface mapping: et-0/0/0=eth0 (mgmt, skip), et-0/0/1=eth1, et-0/0/2=eth2.
PE-PE links are on eth1 and eth2; loopbacks on lo0.
```

---

## Step 2 — Configure OSPF area 0

OSPF provides IGP reachability between PE loopbacks. All PE-PE links and loopbacks are included in area 0.

**Prompt to Claude:**
```
Configure OSPF area 0 on R1, R2 and R3.
Include all PE-PE interfaces and the loopback (lo0.0) as passive.
```

Verify:
```
Ask Claude: show OSPF neighbors on R1, R2 and R3
# Expected: full adjacencies between all PE pairs
```

---

## Step 3 — Configure LDP

LDP distributes MPLS labels over the PE-PE links established by OSPF.

**Prompt to Claude:**
```
Enable LDP on R1, R2 and R3 on all PE-PE interfaces.
```

Verify:
```
Ask Claude: show LDP neighbors on all PEs
# Expected: LDP sessions up between all PE pairs
```

---

## Step 4 — Configure iBGP EVPN full mesh

An iBGP full mesh with address-family `evpn` is established between PE loopbacks.

**Prompt to Claude:**
```
Configure iBGP between R1, R2 and R3 for the EVPN address family.
Use loopback addresses as BGP peers. Full mesh (no route reflector).
```

Verify:
```
Ask Claude: show BGP summary on all PEs
# Expected: 2 established sessions per PE
```

---

## Step 5 — Configure EVPN service

Define the EVPN instance and bind the CE-facing interfaces.

**Prompt to Claude:**
```
Configure an EVPN instance (EVI 100) on R1, R2 and R3.
Bind the CE-facing interface on each PE to the EVI.
R1 and R2 connect to R11; R3 connects to R12.
```

---

## Step 6 — Verify end-to-end

**Prompt to Claude:**
```
Verify the EVPN-MPLS deployment end-to-end:
- Check EVPN routes in the BGP table on all PEs
- Check the MPLS forwarding table
- Verify MAC/IP learning between R11 and R12
```

---

## Rollback

To reset all routers to factory default (hostname + root password only) and start over:

**Prompt to Claude:**
```
Reset R1, R2, R3, R11 and R12 to a clean base configuration:
keep only hostname and root-authentication, remove everything else.
```
