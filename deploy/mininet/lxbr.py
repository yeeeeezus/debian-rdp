"""Linux-bridge switch for Mininet inside user+network namespaces.

The stock OVSSwitch needs the OVS kernel module and /dev/net/tun, neither of
which exists in this container. This switch class uses a plain Linux bridge
(`ip link ... type bridge`), which works unprivileged inside a user namespace
because bridges and veth pairs are namespaced.

The /usr/local/bin/mn wrapper injects --custom + --switch lxbr automatically.
"""
from mininet.node import Switch


class LxBr(Switch):
    """Linux bridge switch (L2 learning, no OpenFlow control plane)."""

    def __init__(self, name, stp=False, **params):
        Switch.__init__(self, name, **params)
        self.stp = stp

    @staticmethod
    def setup():
        pass  # nothing global needed

    def start(self, controllers):
        self.cmd('ip link add name', self, 'type bridge 2>/dev/null || true')
        if self.stp:
            self.cmd('ip link set dev', self, 'type bridge stp_state 1')
        self.cmd('ip link set dev', self, 'up')
        for intf in self.intfList():
            if intf.name != self.name:
                self.cmd('ip link set dev', intf, 'master', self)
                self.cmd('ip link set dev', intf, 'up')

    def stop(self, deleteIntfs=True):
        self.cmd('ip link set dev', self, 'down')
        self.cmd('ip link del dev', self, 'type bridge 2>/dev/null || true')
        Switch.stop(self, deleteIntfs)


switches = {'lxbr': LxBr}
