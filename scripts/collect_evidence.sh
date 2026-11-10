#!/usr/bin/env bash
# Run one Week 5 observation in the official course image, as root with --privileged.
set -euo pipefail

phase=${1:?usage: collect_evidence.sh before|delivery|after|mixed}
mkdir -p /work/assignment/evidence

case "$phase" in
  before)
    # Recreate the finished lab version without changing the assignment checkout.
    old_run=$(mktemp -d)
    cp /work/tunnel_v1.p4 "$old_run/tunnel.p4"
    cp /work/topo.py /work/p4cli /work/s1-commands.txt /work/s2-commands.txt "$old_run/"
    git -c safe.directory=/work -C /work show origin/main:send.py > "$old_run/send.py"
    git -c safe.directory=/work -C /work show origin/main:receive.py > "$old_run/receive.py"
    cd "$old_run"
    evidence=/work/assignment/evidence/loop-before.txt
    cat > "$evidence" <<'NOTE'
Finished lab program on both switches; original four-byte sender/receiver from main.
To keep this deliberately unbounded loop's logs manageable, s1-eth2 has a 10 ms netem delay.
NOTE
    python3 topo.py --id 4940 <<'MININET' >> "$evidence" 2>&1
sh echo '== s2 tunnel table before change =='
sh ./p4cli s2 table_dump MyIngress.myTunnel_exact
sh ./p4cli s2 "table_modify MyIngress.myTunnel_exact MyIngress.myTunnel_forward 2 1"
sh echo '== s2 tunnel table after change =='
sh ./p4cli s2 table_dump MyIngress.myTunnel_exact
sh tc qdisc add dev s1-eth2 root netem delay 10ms
sh tc qdisc show dev s1-eth2
h1 python3 send.py 10.40.0.3 "loop" --tunnel 3
sh echo '== initial switch receive counts =='
sh grep -c 'Processing packet received' logs/s1.txt logs/s2.txt
sh sleep 5
sh echo '== switch receive counts after 5 seconds =='
sh grep -c 'Processing packet received' logs/s1.txt logs/s2.txt
exit
MININET
    ;;
  delivery)
    cd /work
    evidence=assignment/evidence/delivery.txt
    cat > "$evidence" <<'NOTE'
Both switches run the new program. Destination IP deliberately differs from tunnel exit.
NOTE
    python3 topo.py --id 4940 <<'MININET' >> "$evidence" 2>&1
sh sleep 1
h1 python3 send.py 10.40.0.3 "to h2" --tunnel 2
h1 python3 send.py 10.40.0.2 "to h3" --tunnel 3
sh sleep 1
sh echo '== h2 received =='
sh cat logs/h2.txt
sh echo '== h3 received =='
sh cat logs/h3.txt
sh echo '== plain IPv4 ping =='
h1 ping -c 2 h3
exit
MININET
    ;;
  after)
    cd /work
    evidence=assignment/evidence/loop-after.txt
    cat > "$evidence" <<'NOTE'
Both switches run the new program. The same exit-3 loop uses a starting hop limit of 4.
NOTE
    python3 topo.py --id 4940 <<'MININET' >> "$evidence" 2>&1
sh ./p4cli s2 table_dump MyIngress.myTunnel_exact
sh ./p4cli s2 "table_modify MyIngress.myTunnel_exact MyIngress.myTunnel_forward 2 1"
sh echo '== s2 tunnel table after change =='
sh ./p4cli s2 table_dump MyIngress.myTunnel_exact
h1 python3 send.py 10.40.0.3 "bounded" --tunnel 3 --hops 4
sh echo '== initial switch receive counts =='
sh grep -c 'Processing packet received' logs/s1.txt logs/s2.txt
sh sleep 5
sh echo '== switch receive counts after 5 seconds =='
sh grep -c 'Processing packet received' logs/s1.txt logs/s2.txt
sh echo '== end of s1 switch log =='
sh tail -n 45 logs/s1.txt
exit
MININET
    ;;
  mixed)
    cd /work
    evidence=assignment/evidence/mixed.txt
    cat > "$evidence" <<'NOTE'
s1 runs the new five-byte program; s2 runs the saved four-byte tunnel_v1.p4.
The mixed-rollout prediction was committed in assignment/REPORT.md before this run.
NOTE
    python3 topo.py --id 4940 --s2-program tunnel_v1.p4 <<'MININET' >> "$evidence" 2>&1
sh sleep 1
h2 timeout 8 tcpdump -c 1 -XX -ni h2-eth0 ether proto 0x1212 > logs/h2cap.txt 2>&1 &
h1 python3 send.py 10.40.0.3 "mixed" --tunnel 2
sh sleep 8
sh echo '== bytes on h2 link =='
sh cat logs/h2cap.txt
sh echo '== host receiver logs =='
sh cat logs/h2.txt logs/h3.txt
sh echo '== s2 parser and tunnel table log =='
sh grep -E "parse_myTunnel|parse_ipv4|myTunnel_exact|dst_id" logs/s2.txt | tail -n 25
sh echo '== s2 tunnel table before loop =='
sh ./p4cli s2 table_dump MyIngress.myTunnel_exact
sh ./p4cli s2 "table_modify MyIngress.myTunnel_exact MyIngress.myTunnel_forward 2 1"
h1 python3 send.py 10.40.0.3 "mixed-loop" --tunnel 3 --hops 4
sh echo '== initial switch receive counts =='
sh grep -c 'Processing packet received' logs/s1.txt logs/s2.txt
sh sleep 5
sh echo '== switch receive counts after 5 seconds =='
sh grep -c 'Processing packet received' logs/s1.txt logs/s2.txt
sh echo '== end of s1 switch log =='
sh tail -n 45 logs/s1.txt
exit
MININET
    ;;
  *)
    echo "unknown phase: $phase" >&2
    exit 2
    ;;
esac

echo "Collected $phase: $evidence"
