# Week 5 lab

This folder contains the finished four-byte tunnel lab as a runnable project.
In the course Codespace or another privileged x86 environment, run:

```bash
cd lab
python3 topo.py --id 4940
```

`tunnel.p4`, `send.py`, and `receive.py` are the finished Step 5 versions.
`tunnel_initial.p4` is the untouched template used for Steps 1–3.
`collect.sh` creates temporary Step 4 and Step 6 variants, runs all stages in
Mininet, and writes the outputs to `evidence/`. The deliberate broken
deparser is only in a temporary copy.

Read [NOTES.md](NOTES.md) for the observations and wrap-up answers. The four
evidence files are [base.txt](evidence/base.txt),
[parser.txt](evidence/parser.txt), [table.txt](evidence/table.txt), and
[broken.txt](evidence/broken.txt).
