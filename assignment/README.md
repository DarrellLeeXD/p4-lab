# Week 5 assignment — Tunnel hop limit

This folder contains the runnable hop-limit solution and the required
[report](REPORT.md). In the course Codespace or another privileged x86
environment, run:

```bash
cd assignment
python3 topo.py --id 4940
```

For the mixed-rollout experiment, run
`python3 topo.py --id 4940 --s2-program tunnel_v1.p4`.
`tunnel.p4`, `send.py`, and `receive.py` use the five-byte header.
`tunnel_v1.p4` and the host scripts in `legacy/` preserve the finished
four-byte lab format. `collect.sh` records C1–C5 in `evidence/`.

From this folder, run the host tests with
`python3 -m unittest discover -s tests -q` and check the recorded experiments
with `python3 check_evidence.py`.

The submission is the open [Tunnel hop limit pull request](https://github.com/DarrellLeeXD/p4-lab/pull/1).
Spectrum has that pull request URL.
