from mininet.net import Mininet
from mininet.node import RemoteController, OVSSwitch
from mininet.cli import CLI
from mininet.log import setLogLevel

def run():
    # Ring with a backup link; STP keeps loops from forming.
    # Run controller app: ryu-manager ryu.app.simple_switch_stp_13
    net = Mininet(controller=None, switch=OVSSwitch)
    net.addController('c0', controller=RemoteController,
                     ip='127.0.0.1', port=6653)
    switches = []
    for i in range(1, 4):
        sw = net.addSwitch(f's{i}', protocols='OpenFlow13')
        h = net.addHost(f'h{i}', ip=f'10.0.0.{i}/24')
        net.addLink(h, sw)
        switches.append(sw)
    for i in range(2):
        net.addLink(switches[i], switches[i+1])
    net.addLink(switches[2], switches[0])    # backup link closes the ring
    try:
        net.start(); net.pingAll(); CLI(net)
    finally:
        net.stop()

setLogLevel('info')
run()
