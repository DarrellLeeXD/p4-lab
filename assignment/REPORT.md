# Week 5 assignment — Put a limit on the tunnel

Student ID suffix: **4940**. The Mininet hosts are `10.40.0.1`–`10.40.0.3`.

## 1. Analysis: the loop

I started with the finished Step 5 program saved as `tunnel_v1.p4`. On s2,
`sh ./p4cli s2 table_dump MyIngress.myTunnel_exact` showed that the exit-3
entry had handle `0x2` and sent to port 3. I changed it with
`sh ./p4cli s2 "table_modify MyIngress.myTunnel_exact MyIngress.myTunnel_forward 2 1"`.
Now s1 sends exit 3 to s2, and s2 sends it back to s1. I sent one packet from
h1 with `--tunnel 3`. In [loop-before.txt](evidence/loop-before.txt), the
switch receive counters went from **0 to 480 on s1** and **0 to 479 on s2**
over five seconds. I added 10 ms delay to `s1-eth2` for this deliberately
unbounded run so the logs would remain manageable; the repeated visits still
continued until Mininet exited.

The old `ipv4_forward` action subtracts one from the 8-bit IPv4 TTL, but the
ingress has no zero-TTL drop check. At zero, another subtraction can wrap the
field to 255. This program therefore does not reliably stop a plain IPv4
forwarding loop either. More directly, a tunnelled packet takes
`myTunnel_forward`, which never invokes `ipv4_forward`: the inner IPv4 TTL
stays at 64 throughout this tunnel loop.

## 2. Design: the hop limit

I appended an **8-bit `hops` field** after the existing 16-bit `proto_id` and
16-bit `dst_id`. One byte permits values from 0 to 255, adds only one byte per
tunnel packet, and leaves the old fields at their original offsets. The sender
defaults to **4** and accepts `--hops 0..255`. Four allows the normal two-switch
path to reach a host with 2 left, while limiting a loop to a few passes.

On each upgraded switch, ingress first checks a valid tunnel header. If `hops`
is zero, it drops the packet. Otherwise it subtracts one and then looks up
`dst_id` in `myTunnel_exact`. Checking before subtraction prevents zero from
wrapping to 255. The parser and deparser handle the five-byte header, and both
Scapy host programs use that same field order and size. With a starting value
of 4, two upgraded switches should each forward twice; the fifth switch visit
should drop the packet (s1: three visits, s2: two).

## 3. Implementation

`tunnel.p4` declares `bit<8> hops` and adds the zero check and decrement in the
tunnel ingress branch. The tunnel table still forwards by `dst_id`, and the
plain IPv4 branch remains separate. `send.py` adds the byte to its Scapy
`MyTunnel` header, sets a default of 4, and rejects an out-of-range `--hops`
or `--hops` without `--tunnel`. `receive.py` parses the longer header and
prints the arriving hop value. `tunnel_v1.p4` retains the complete Step 5
program for the comparison, and `assignment/collect.sh` records each
experiment in the course container.

## 4. Evidence: it works

[delivery.txt](evidence/delivery.txt) shows h2 receiving payload `to h2` with
`dst_id=2, hops=2`, although its inner IP destination is h3 (`10.40.0.3`).
It also shows h3 receiving `to h3` with `dst_id=3, hops=2`, although its inner
IP destination is h2 (`10.40.0.2`). Thus both tunnel exits use the tunnel
table, and both switches decremented once. A plain h1-to-h3 ping returned
**2/2 replies**, with reply TTL 62.

In a fresh network, I repeated the same exit-3 table change and sent one
packet with `--hops 4`. [loop-after.txt](evidence/loop-after.txt) records s1
**6→9** and s2 **6→8**: five additional switch visits total. The final s1
log says `hdr.myTunnel.hops == 0` and runs `MyIngress.drop`. That is the
predicted four forwards followed by a drop; the counters did not grow during
the five-second observation window.

## 5. Evaluation

**Mixed-rollout prediction, recorded before running C5.** The old s2 will
still read `proto_id` and `dst_id` correctly because I appended the new byte.
It should select the same tunnel output port. But it will start parsing IPv4
at the hop byte, one byte before the real IPv4 header. Its deparser may emit
the same bytes, yet its unconditional IPv4 checksum recomputation may change
bytes belonging to the real IPv4 protocol/checksum. I therefore predict that
an Ethernet frame will reach h2 but `receive.py` may not recognise it as our
UDP packet. In the loop, upgraded s1 decrements once per visit while old s2
does not; starting at 4 should take nine switch processings before s1 drops
the packet at zero, rather than five with two upgraded switches.

**What happened.** [mixed.txt](evidence/mixed.txt) shows that h2 *did* print
the `mixed` UDP payload with `hops=3` and inner TTL 64. The first four tunnel
bytes, `08 00 00 02`, retain their old positions; old s2 therefore hits the
exit-2 table entry. Its four-byte parser then treats the fifth byte (`03`,
after s1's decrement) as the start of IPv4, followed by the first 19 real
IPv4 bytes. `tcpdump` on h2 shows `08 00 00 02 03 45 ...`, so the five-byte
tunnel header and real `45` IPv4 start were still emitted intact.

The successful delivery is a coincidence of these packet values, not a safe
compatibility guarantee. For this packet, the destination IP ends in `03`,
the same value as the misread starting `hops` byte. Old s2's falsely aligned
20-byte IPv4 header is therefore the real header rotated by one byte. Its
false checksum field contains `11 66` (the real UDP protocol byte and first
checksum byte). Recomputing the checksum on those falsely aligned bytes also
gives `0x1166`, so s2 does not change them. If the incoming hop byte were
`04` instead, the calculation would give `0x1066`, changing the real IP
protocol byte from `0x11` (UDP) to `0x10`. The observed success must not be
used to assume that old switches can safely parse this new format.

For the mixed loop, [mixed.txt](evidence/mixed.txt) records s1 **10→15** and
s2 **9→13**: nine visits total. s1 logs its zero-hop drop. The loop ended as
predicted, but needed four more visits than the all-upgraded case because s2
did not decrement. A loop entirely among old switches would have no such
protection.

**Rollout.** One option is to assign a new `proto_id` value to the new tunnel
format, while retaining `dst_id` at its old offset. In this particular old
program, s2 would then select `accept` instead of `parse_ipv4`; it could
forward by `dst_id` while leaving the rest of the packet opaque. Upgrade
switches to understand both formats, test this pass-through behavior on the
target, then enable the new format at senders. This keeps traffic moving but
old switches still do not enforce `hops`, so paths need an upgraded guard and
the control plane must reject old-only loops. A second option is a **new
EtherType** for version 2: old switches drop the unknown type instead of
silently misparsing it. Install dual-format support across each entire path
before senders emit version 2. This fails closed and is easier to reason
about, but requires coordinated path upgrades or temporarily blocks traffic.
Simply appending the byte under the old identifiers, as this experiment did,
is unsafe.

Week 3's `check_paths()` follows configured routes for every host pair before
building the network. It can find a repeated router or missing route and
reject that configuration before any packet is sent; this is more informative
than a packet drop and can reveal a path that no test packet has tried. It
only knows the route specification it inspected, however. It cannot stop a
loop caused later by a changed live table entry, stale device state, or a
packet taking an unexpected tunnel path. The data-plane hop check acts on
each actual tunnel packet and bounds those runtime loops, but only after some
forwards have happened; it does not explain or repair the bad route. Real
networks use both preflight control-plane checks and per-packet limits.

On hardware, the cost is one header byte per tunnelled packet (sometimes
absorbed by Ethernet minimum-frame padding), one extra parser extraction,
an 8-bit zero comparison and decrement, a conditional drop decision, and
emitting the byte. At line rate these must fit the target's parser and match
action pipeline resources; if no stage or ALU capacity remains, the program
may need a different layout or fail to compile for that chip. The added
header slightly reduces useful payload capacity and could push a packet over
an MTU. It does not change the inner IPv4 checksum when parsed correctly.

## AI use

I used **OpenAI Codex** to read the Week 5 instructions, help design and
implement the P4 and Scapy changes, write packet tests, run the course image
through GitHub Actions, inspect the Mininet and packet-capture evidence, and
draft this report and the pull request. The committed pre-experiment
prediction and the four evidence files distinguish the prediction from the
observed results.

## Evidence files

| File | Observation |
| --- | --- |
| [loop-before.txt](evidence/loop-before.txt) | Old program's continuing tunnel loop |
| [delivery.txt](evidence/delivery.txt) | Both tunnel exits and plain IPv4 ping |
| [loop-after.txt](evidence/loop-after.txt) | Five visits and zero-hop drop |
| [mixed.txt](evidence/mixed.txt) | Old s2's parsing, packet bytes, and nine-visit loop |
