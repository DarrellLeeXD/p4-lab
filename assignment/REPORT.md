# Week 5 assignment — Put a limit on the tunnel

Student ID (last 4 digits only): **4940**

Write each section in your own words, about your own runs. Quote the evidence files in
`assignment/evidence/` that support each point. Delete the instructions in `<!-- -->` as you go.

## 1. Analysis: the loop

<!-- How did you create the tunnel loop (which entry, on which switch, which commands)?
     What did the switch logs show over time, with numbers from loop-before.txt?
     Then look at the IPv4 path in tunnel.p4: it decrements the TTL. Does that stop an IPv4
     loop in this program? Check the code, and explain what happens when TTL reaches 0. -->

## 2. Design: the hop limit

I appended an 8-bit `hops` field after `proto_id` and `dst_id`. One byte is
enough for 0–255 switch forwards and keeps the first four bytes of the old
header at the same offsets, so the mixed-rollout experiment can show what an
old switch does with the additional byte. The sender starts at 4 by default:
the two-switch normal path delivers with 2 left, and a loop can be observed
briefly without producing an unbounded packet storm. `--hops` allows an
explicit value from 0 to 255.

Every upgraded switch checks `hops` before the tunnel table. At zero it drops
the packet; otherwise it subtracts one and applies `myTunnel_exact`. Checking
first prevents an 8-bit underflow from turning 0 into 255. The parser extracts
the longer header and the deparser emits it, while Scapy in `send.py` and
`receive.py` uses the same field order and width. A two-switch delivery should
therefore arrive with `hops=2`. A loop starting at 4 should be processed by
five upgraded switches: four forwards, then a drop at the fifth.

## 3. Implementation

<!-- Summarise what you changed in tunnel.p4, send.py and receive.py. The pull request shows
     the code itself: here, explain anything a reviewer might not see from the diff alone. -->

## 4. Evidence: it works

<!-- Show, with your evidence files:
     - tunnelled delivery to h2 and h3, and the hop limit the receivers saw (delivery.txt);
     - plain IPv4 still works (delivery.txt);
     - the same loop as in section 1 now ends, and after how many passes — does that match
       your design? (loop-after.txt) -->

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

<!-- a) The mixed rollout (mixed.txt): what did you predict before running s1 with your new
        program and s2 with tunnel_v1.p4? What actually happened to delivery, and to the loop?
        Explain every difference from your prediction, byte by byte if you need to.
     b) Propose a safe way to roll out a header change across a network of switches that can't
        all be upgraded at once. Compare at least two options (for example a version field, a
        new EtherType, or ordering fields so old switches still parse them).
     c) Loop protection in the data plane (this hop limit) versus the control plane (Week 3's
        check_paths()): what can each catch that the other can't? Why do real networks use both?
     d) What would this change cost on a hardware switch running at line rate? -->

## AI use

I used OpenAI Codex to read the assignment, design and implement the P4 and
Scapy changes, write packet tests, run the course image in GitHub Actions,
interpret the resulting switch and host logs, and help draft this report and
the pull request. The evidence files identify the commands and observations;
I will review the implementation and should be able to explain and defend it.

## Evidence files

| File | What it shows |
|---|---|
| `evidence/loop-before.txt` | The loop with your finished lab program: pass counts growing |
| `evidence/delivery.txt` | Tunnelled delivery with the hop limit, and a plain ping |
| `evidence/loop-after.txt` | The same loop with your hop limit: pass counts that stop |
| `evidence/mixed.txt` | The mixed rollout: s1 new, s2 old |
