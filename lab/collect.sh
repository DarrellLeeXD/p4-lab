#!/usr/bin/env bash
# Reproduce the separate Week 5 lab stages in the official course image.
set -euo pipefail

phase=${1:?usage: collect_lab.sh base|parser|table|broken}
case "$phase" in
  base|parser|table|broken) ;;
  *) echo "unknown phase: $phase" >&2; exit 2 ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp /work/lab/topo.py /work/lab/p4cli /work/lab/s1-commands.txt /work/lab/s2-commands.txt "$work/"
cp /work/lab/send.py /work/lab/receive.py "$work/"

if [[ $phase == base ]]; then
  cp /work/lab/tunnel_initial.p4 "$work/tunnel.p4"
else
  python3 - "$phase" "$work/tunnel.p4" <<'PY'
from pathlib import Path
import sys

phase, target = sys.argv[1:]
source = Path('/work/lab/tunnel.p4').read_text()
if phase == 'parser':
    old = '''    apply {
        if (hdr.myTunnel.isValid()) {
            myTunnel_exact.apply();
        } else if (hdr.ipv4.isValid()) {
            ipv4_lpm.apply();
        } else {
            drop();
        }
    }
'''
    new = '''    apply {
        if (hdr.ipv4.isValid()) {
            ipv4_lpm.apply();
        } else {
            drop();
        }
    }
'''
elif phase == 'broken':
    old = '        packet.emit(hdr.myTunnel);'
    new = '        // packet.emit(hdr.myTunnel);'
else:
    old = new = ''
if old:
    assert source.count(old) == 1, f'expected one lab edit for {phase}'
    source = source.replace(old, new)
Path(target).write_text(source)
PY
fi

cd "$work"
evidence="/work/lab/evidence/$phase.txt"
mkdir -p /work/lab/evidence
printf 'Week 5 lab phase: %s. Student ID suffix: 4940.\n' "$phase" > "$evidence"

case "$phase" in
  base)
    cat >> "$evidence" <<'NOTE'
Original template program: Step 1 start, Step 2 IPv4, Step 3 live table edits.
NOTE
    python3 topo.py --id 4940 <<'MININET' >> "$evidence" 2>&1
sh echo '== Step 2: IPv4 pings =='
h1 ping -c 3 h2
h1 ping -c 3 h3
sh echo '== s1 IPv4 table applications =='
sh grep -m 4 "Applying table 'MyIngress.ipv4_lpm'" logs/s1.txt
sh echo '== Step 3: s2 IPv4 table before deletion =='
sh ./p4cli s2 table_dump MyIngress.ipv4_lpm
sh ./p4cli s2 table_delete MyIngress.ipv4_lpm 2
sh echo '== h3 ping with route deleted =='
h1 ping -c 2 -W 1 h3
sh echo '== s2 default drop after miss =='
sh grep -E "Table 'MyIngress.ipv4_lpm': miss|Action MyIngress.drop" logs/s2.txt | tail -n 8
sh ./p4cli s2 "table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward 10.40.0.3/32 => 3"
sh echo '== h3 ping after restoring route =='
h1 ping -c 2 h3
h1 python3 send.py 10.40.0.3 "test 1" --tunnel 2
sh sleep 1
sh echo '== test 1 host logs =='
sh cat logs/h2.txt logs/h3.txt
sh echo '== s1 unrecognized tunnel EtherType =='
sh grep 'key is 1212' logs/s1.txt | tail -n 1
exit
MININET
    ;;
  parser)
    cat >> "$evidence" <<'NOTE'
Step 4: tunnel parser and deparser added; ingress still forwards by IPv4.
NOTE
    python3 topo.py --id 4940 <<'MININET' >> "$evidence" 2>&1
h1 python3 send.py 10.40.0.3 "test 2" --tunnel 2
sh sleep 1
sh echo '== test 2 host logs =='
sh cat logs/h2.txt logs/h3.txt
sh echo '== s1 IPv4 table application =='
sh grep "Applying table 'MyIngress.ipv4_lpm'" logs/s1.txt | tail -n 1
exit
MININET
    ;;
  table)
    cat >> "$evidence" <<'NOTE'
Step 5: finished four-byte tunnel parser, tunnel table and deparser.
NOTE
    python3 topo.py --id 4940 <<'MININET' >> "$evidence" 2>&1
h1 python3 send.py 10.40.0.3 "test 3" --tunnel 2
sh sleep 1
sh echo '== test 3 host logs =='
sh cat logs/h2.txt logs/h3.txt
sh echo '== plain IPv4 ping =='
h1 ping -c 2 h3
exit
MININET
    ;;
  broken)
    cat >> "$evidence" <<'NOTE'
Step 6: temporary copy with tunnel deparser emission commented out.
The committed tunnel_v1.p4 retains packet.emit(hdr.myTunnel).
NOTE
    python3 topo.py --id 4940 <<'MININET' >> "$evidence" 2>&1
h1 python3 send.py 10.40.0.3 "test 4" --tunnel 2
sh sleep 1
sh echo '== test 4 host logs =='
sh cat logs/h2.txt logs/h3.txt
sh echo '== s1 parsed and forwarded tunnel =='
sh grep -E "key is 1212|hdr.myTunnel.dst_id : 0002|MyIngress.myTunnel_forward|Transmitting packet" logs/s1.txt | tail -n 12
sh echo '== s2 misparsed packet and dropped =='
sh grep -E "Parser state 'parse_myTunnel': key is|hdr.myTunnel.dst_id : 0022|Action MyIngress.drop" logs/s2.txt | tail -n 12
exit
MININET
    ;;
esac

# Mininet's PTY uses CRLF and adds trailing spaces; keep the evidence diff-clean.
python3 - "$evidence" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_bytes().replace(b'\r\n', b'\n').split(b'\n')
path.write_bytes(b'\n'.join(line.rstrip(b' \t') for line in lines))
PY

echo "Collected $phase: $evidence"
