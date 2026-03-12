# IT VPN request (CLOPR2 DR France Central)

## Summary
We are preparing a DR site in Azure France Central. We need to establish a site-to-site IPsec VPN between the school network and Azure.

## Required values from IT
- **On-prem VPN device public IP** (static)
- **IKE/IPsec parameters** (confirm supported settings):
  - IKEv2 support
  - Encryption and integrity algorithms
  - DH group
  - PFS group
  - SA lifetimes
- **Routing confirmation**:
  - Allow routes between Azure DR `10.20.0.0/16` and on-prem `10.0.0.0/16`
- **NAT requirements** (if required, provide translated ranges)
- **Allowed protocols/ports**:
  - UDP 500, UDP 4500, ESP

## Our side (Azure DR)
- **Region**: France Central
- **Azure DR VNet**: `10.20.0.0/16`
- **DR subnet**: `10.20.2.0/24`
- **GatewaySubnet**: `10.20.255.0/27`
- **On-prem address space (expected)**: `10.0.0.0/16`

## Outcome
Once values are confirmed, we will enable the VPN gateway resources and configure the connection in Azure.
