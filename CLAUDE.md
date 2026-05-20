# context-lab42 — interaction rules

## Scope

This lab contains only the following cRPD routers: r1, r2, r3, r11, r12.  
Management addresses: 192.168.100.2 to 192.168.100.6.

## Absolute rule — device access

For any interaction with the routers (show, config, diagnostic),
use EXCLUSIVELY the junos-mcp MCP tools:

- `execute_junos_command`
- `get_junos_config`
- `load_and_commit_config`
- `junos_config_diff`
- `gather_device_facts`
- `get_router_list`

NEVER use: bash, ssh, docker exec, direct NETCONF, or any access outside MCP —
even if the MCP is unavailable.  
If the MCP server does not respond, report it and stop.

## Configuration change rule

Before any `load_and_commit_config`:

1. Display the diff with `junos_config_diff`
2. Wait for explicit confirmation

## Out of scope

This MCP server covers this lab only. Do not use it for other Junos devices,
even if their IPs are reachable from this network.
