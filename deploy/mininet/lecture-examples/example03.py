from mininet.net import Mininet
from mininet.node import RemoteController, OVSSwitch
from mininet.cli import CLI
from mininet.log import setLogLevel

def run():
    net = Mininet(controller=None, switch=OVSSwitch)
    net.addController('c0', controller=RemoteController,
                     ip='127.0.0.1', port=6653)
    switches = []
    for i in range(1, 4):                    # 3 switches
        sw = net.addSwitch(f's{i}', protocols='OpenFlow13')
        switches.append(sw)
    for i in range(1, 4):                    # one host per switch
        h = net.addHost(f'h{i}', ip=f'10.0.0.{i}/24')
        net.addLink(h, switches[i-1])
    for i in range(2):                       # chain s1-s2-s3
        net.addLink(switches[i], switches[i+1])
    try:
        net.start(); net.pingAll(); CLI(net)
    finally:
        net.stop()

setLogLevel('info')
run()
