from mininet.net import Mininet
from mininet.node import RemoteController, OVSSwitch
from mininet.cli import CLI
from mininet.log import setLogLevel
from mininet.topo import Topo

class MyTopo(Topo):
    def build(self, count=3, per_switch=2):
        switches = []
        for s in range(1, count+1):
            sw = self.addSwitch(f's{s}', protocols='OpenFlow13')
            switches.append(sw)
        for s in range(count):
            for h in range(1, per_switch+1):
                hid = s*per_switch + h
                host = self.addHost(f'h{hid}', ip=f'10.0.0.{hid}/24')
                self.addLink(host, switches[s])
        for i in range(len(switches)-1):
            self.addLink(switches[i], switches[i+1])

def run():
    net = Mininet(topo=MyTopo(count=3, per_switch=2),
                  controller=None, switch=OVSSwitch)
    net.addController('c0', controller=RemoteController,
                     ip='127.0.0.1', port=6653)
    try:
        net.start(); net.pingAll(); CLI(net)
    finally:
        net.stop()

setLogLevel('info')
run()
