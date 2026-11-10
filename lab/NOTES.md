# Week 5 lab notes — Programmable Data Planes

Student ID suffix: **4940**. The hosts used `10.40.0.1`–`10.40.0.3`.
The experiments ran in the course's x86 container through
[GitHub Actions run 42772978263](https://github.com/DarrellLeeXD/p4-lab/actions/runs/42772978263).
The script recreated each temporary program state from files in this folder.
The finished Step 5 program is `lab/tunnel.p4`; the same version remains on
`main` and is saved as `assignment/tunnel_v1.p4` for the mixed-rollout test.

## Steps 0–3: the original program

The lab template is in my public `p4-lab` repository. The original program
compiled, but warned that `TYPE_MYTUNNEL` and `myTunnel_exact` were unused;
`topo.py` added three IPv4 entries to each switch and skipped the tunnel
entries. In [base.txt](evidence/base.txt), h1's three pings to h2 and three to
h3 all received replies. The replies had TTL **62**, and the s1 log shows
`MyIngress.ipv4_lpm` being applied.

On s2, the IPv4 route to h3 (`10.40.0.3/32`) was handle `0x2`, with output
port 3. I deleted it using `p4cli` while the network was running: the next
ping to h3 got **0/2** replies, and s2 logged an IPv4 table miss followed by
`MyIngress.drop`. Adding the route back restored **2/2** replies, without
recompiling. I then sent `test 1` to IP h3 with tunnel exit 2. Neither host
received it. s1's parser logged Ethernet type `1212`, but this original
program had no transition for that type, so its ingress had no valid IPv4
header to forward.

## Step 4: parse and emit the tunnel

I added the `TYPE_MYTUNNEL` parser transition, a `parse_myTunnel` state, and
`packet.emit(hdr.myTunnel)` in the deparser. The ingress still applied only
`ipv4_lpm`. [parser.txt](evidence/parser.txt) shows `test 2` arriving at
**h3**, despite `dst_id=2`, with TTL **62**. Both switches forwarded by the
inner IPv4 destination and each decremented TTL. The tunnel header remained
on the packet because the deparser emitted the valid header. The compiler
still warned that `myTunnel_exact` was unused.

## Step 5: use the tunnel table

I changed ingress to apply `myTunnel_exact` for valid tunnel headers and
`ipv4_lpm` for plain IPv4. Both switches then loaded six entries, with no
unused-table warning. In [table.txt](evidence/table.txt), `test 3` reached
**h2** with inner destination `10.40.0.3` and TTL **64**. Tunnel forwarding
used `dst_id=2` and did not call `ipv4_forward`, so the inner TTL stayed
unchanged. Plain h1-to-h3 IPv4 ping still returned **2/2** replies at TTL 62.

## Step 6: remove the deparser line temporarily

I compiled a temporary copy with `packet.emit(hdr.myTunnel)` commented out,
then sent `test 4`. [broken.txt](evidence/broken.txt) shows no delivery to
either host, although compilation succeeded. s1 parsed Ethernet type `1212`,
looked up `dst_id=2`, and transmitted out port 2. Because the tunnel header
was omitted, s2 saw the first four bytes of IPv4 as its supposed tunnel
header. Its parser reported `proto_id=0x4500`: IPv4 version/IHL `0x45` and
type of service `0x00`. Its tunnel table saw `dst_id=0x0022`, the IPv4 total
length of **34 bytes** (20-byte IP header, 8-byte UDP header, 6-byte message).
No exit 34 exists, so s2 dropped the packet. The committed program still
emits the tunnel header; the intentional break affected only the temporary
copy used for this observation.

## Wrap-up answers

1. Besides deleting and restoring h3's IPv4 route, a controller could change
   the output port for h2's IPv4 route and change the port for tunnel exit 3
   in `myTunnel_exact` at run time. Adding a new header field or parser state
   needs a new P4 program, as does changing which table the ingress applies.
2. Step 4's packet reached h3 because ingress still chose the IPv4 route to
   `10.40.0.3`; `dst_id=2` was parsed but not used. It remained tunnelled
   because the deparser wrote the valid tunnel header back out.
3. Step 5's tunnel path used `myTunnel_forward`, which did not decrement the
   inner IPv4 TTL, so it arrived at 64. Plain pings used `ipv4_forward` on
   both switches and their replies showed TTL 62.
4. The compiler identified the unused tunnel constant and table in the
   original program, and the unused table in Step 4. It found no issue with
   the Step 6 deparser omission: the program was syntactically valid, but its
   Ethernet type no longer matched the bytes after Ethernet. P4 compilation
   checks program structure; packet tests and switch logs are needed to catch
   this kind of forwarding error.
