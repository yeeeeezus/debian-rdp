from mininet.net import Mininet
from mininet.node import RemoteController, OVSSwitch
from mininet.cli import CLI
from mininet.log import setLogLevel

def run():
    net = Mininet(controller=None, switch=OVSSwitch)
    net.addController('c0', controller=RemoteController,
                     ip='127.0.0.1', port=6653)
    s1 = net.addSwitch('s1', protocols='OpenFlow13')
    hosts = []
    for i in range(1, 5):                    # 4 hosts: h1..h4
        h = net.addHost(f'h{i}', ip=f'10.0.0.{i}/24')
        net.addLink(h, s1)
        hosts.append(h)
    try:
        net.start(); net.pingAll(); CLI(net)
    finally:
        net.stop()

setLogLevel('info')
run()
