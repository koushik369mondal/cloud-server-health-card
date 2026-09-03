# Step 0 — create the VM

Pick your cloud. This is the **only** part of the lab that differs. Everything after this is identical.

Whichever you use, you are doing the same four things:

1. Create a Windows Server 2022 VM, smallest size available
2. Get an Administrator password for it
3. Open **3389** (RDP) and **80** (HTTP) inbound — **from your own IP only**
4. Note the region, zone and machine size so you can put them in `deployment.json`

Get your own public IP first, from `checkip.amazonaws.com` or by searching "what is my IP". You will need it for the firewall rules.

> Use your own IP as the source, never `0.0.0.0/0`. This VM will publish its own hostname and IP address on a web page. Do not hand that to the whole internet.

---

## AWS — EC2

1. EC2 console → **Launch instance**
2. Name: `iis-lab-<yourname>`
3. AMI: **Microsoft Windows Server 2022 Base**
4. Instance type: `t3.micro`
5. Key pair: create `iis-lab-key`, download the `.pem`. **Lose it and you lose the VM.**
6. Network settings → Edit → create a security group with two inbound rules:
   - RDP · TCP 3389 · Source **My IP**
   - HTTP · TCP 80 · Source **My IP**
7. Storage: 30 GB gp3
8. Launch, wait for **2/2 status checks**

**Password:** select the instance → **Connect** → **RDP client** tab → **Get password** → upload your `.pem` → **Decrypt password**.

**Connect:** RDP to the **Public IPv4 address**, user `Administrator`.

**For `deployment.json`:** cloud `AWS`, region e.g. `ap-south-1`, zone e.g. `ap-south-1b`, size `t3.micro`.

---

## Azure — Virtual Machines

1. Portal → **Virtual machines** → **Create** → Azure virtual machine
2. Resource group: create `rg-iis-lab`
3. Name: `vm-iis-lab`
4. Region: pick one near you, e.g. Central India
5. Availability options: **No infrastructure redundancy required** (or pick a zone and note it)
6. Image: **Windows Server 2022 Datacenter: Azure Edition — x64 Gen2**
7. Size: `Standard_B1s` or `B2s`
8. **Administrator account:** you set the username and password here. Do not use `admin` or `administrator` — Azure rejects both. Write the password down.
9. Inbound port rules: select **RDP (3389)** for now
10. Review + create

**Lock down the firewall after creation** — the wizard's port rules default to *Any* source, which is not what you want:

1. Go to the VM → **Networking** → the network security group
2. Edit the RDP rule: change Source to **IP Addresses** and enter *your* IP with `/32`
3. **Add inbound port rule**: TCP 80, Source = your IP `/32`, priority 310, name `Allow-HTTP-MyIP`

**Connect:** RDP to the VM's public IP with the username and password you chose.

**For `deployment.json`:** cloud `Azure`, region e.g. `centralindia`, zone `1` or `none`, size `Standard_B1s`.

---

## GCP — Compute Engine

1. Console → **Compute Engine** → **VM instances** → **Create instance**
2. Name: `vm-iis-lab`
3. Region and zone: pick one near you, e.g. `asia-south1` / `asia-south1-a`
4. Machine type: `e2-micro` or `e2-small`
5. Boot disk → **Change** → Operating system **Windows Server** → version **Windows Server 2022 Datacenter**, 50 GB
6. Firewall: tick **Allow HTTP traffic** — note that this creates a rule open to `0.0.0.0/0`, which you will fix in a moment
7. Create

**Fix the firewall** (this is part of the lab, not a detour):

1. VPC network → **Firewall**
2. Find `default-allow-rdp`. It allows 3389 from `0.0.0.0/0`. **Disable or delete it.**
3. Find `default-allow-http` and either delete it, or edit the source range to your own IP `/32`
4. **Create firewall rule**: name `allow-lab-myip`, targets **Specified target tags** → tag `iis-lab`, source IPv4 range = your IP `/32`, protocols TCP `80,3389`
5. Edit the VM → **Network tags** → add `iis-lab` → Save

GCP firewall rules live at the *network* level and attach to VMs by tag, rather than being attached to the VM directly. That difference is worth understanding before you move on.

**Password:** select the VM → **Set Windows password** → enter a username → copy the generated password.

**Connect:** RDP to the **External IP**.

**For `deployment.json`:** cloud `GCP`, region e.g. `asia-south1`, zone e.g. `asia-south1-a`, size `e2-micro`.

---

## What just differed, and what didn't

| | AWS | Azure | GCP |
|---|---|---|---|
| Firewall object | Security group | Network security group | VPC firewall rule + network tags |
| Attached to | The instance | The NIC / subnet | The network, matched by tag |
| Default openness | Nothing open until you say so | Wizard defaults to Any source | Ships with RDP open to the world |
| Admin password | Decrypt with your key file | You choose it at create time | Generated on request afterwards |
| Public IP on stop/start | Changes | Usually kept | Changes |

Three different models for the same job: *decide who may reach this machine on which port*. Everything after this step is plain Windows and is identical on all three.

Now go back to the [README](../README.md) and continue from Step 1.
