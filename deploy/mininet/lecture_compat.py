"""Lecture compatibility layer for the Mininet SDN lab.

Lecture scripts import OVSSwitch + RemoteController and expect a Ryu
controller at 127.0.0.1:6653. This sandbox has no OVS kernel module, so:

  * OVSSwitch        -> LxBr (Linux bridge, L2 learning)
  * RemoteController -> Controller (local, harmless: bridges don't need one)
  * protocols=       -> ignored gracefully

Import this BEFORE mininet (sitecustomize does it automatically):
    import lecture_compat
"""
import mininet.node as _node

import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from lxbr import LxBr   # noqa: F401

# --- switch alias ---------------------------------------------------------
_node.OVSSwitch = LxBr

# --- controller alias ------------------------------------------------------
# RemoteController(ip, port) is accepted but mapped to a no-op local
# controller so net.addController(...) never tries a TCP connect that would
# hang the script start.
class _LectureController(_node.Controller):
    """Local controller stub - bridges learn L2 by themselves."""
    def start(self):
        pass

    def stop(self):
        pass

_node.RemoteController = _LectureController


# --- userspace loop-guard (kernel STP can't run in a user namespace) --------
# Kernel bridges here never exchange BPDUs (each stays its own root), so a
# ring topology would flood forever. The lecture's example06 pairs the ring
# with simple_switch_stp_13; the compat layer reproduces STP's *effect* for
# bridge-based labs: after net.start(), Mininet's Mininet.stop is untouched,
# but we wrap Mininet.start to scan links; when switches form a cycle, we
# administratively down ONE redundant switch-to-switch port (the "backup
# link"), exactly what STP's blocking port does. 'link up' restores it.
import mininet.net as _net

_orig_start = _net.Mininet.start
def _start_with_loopguard(self, *a, **k):
    _orig_start(self, *a, **k)
    # build switch adjacency
    adj = {}
    for l in self.links:
        i1, i2 = l.intf1, l.intf2
        n1 = getattr(i1.node, 'name', None); n2 = getattr(i2.node, 'name', None)
        is_sw = lambda n: n in getattr(self, 'switches', []) or str(n).startswith('s')
        if is_sw(n1) and is_sw(n2):
            adj.setdefault(n1, []).append((n2, i1))
            adj.setdefault(n2, []).append((n1, i2))
    # BFS from the first switch; mark back-edges (ring closers)
    if not adj:
        return
    seen = {}
    from collections import deque
    start = sorted(adj)[0]
    q = deque([start]); seen[start] = None
    for n, i in adj.get(start, []):
        pass
    while q:
        u = q.popleft()
        for v, intf in adj.get(u, []):
            if v not in seen:
                seen[v] = u
                q.append(v)
            elif v != seen[u]:
                # back edge: block ONE direction of this redundant link
                try:
                    intf.node.cmd('ip link set dev', intf.name, 'down')
                    print('*** loop-guard: STP-style block on', intf.name,
                          '(kernel STP unavailable in userns)')
                except Exception:
                    pass
                return   # one blocked port is enough for a single ring
_net.Mininet.start = _start_with_loopguard
