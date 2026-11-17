from mininet.net import Mininet
from mininet.node import RemoteController, OVSSwitch
from mininet.cli import CLI
from mininet.log import setLogLevel

def run():
    net = Mininet(controller=None, switch=OVSSwitch)
    net.addController('c0', controller=RemoteController,
                     ip='127.0.0.1', port=6653)
    core = net.addSwitch('s1', protocols='OpenFlow13')
    branches = [(2, [1, 2]), (3, [3, 4])]   # (access switch id, its host ids)
    for sw_id, host_ids in branches:
        access = net.addSwitch(f's{sw_id}', protocols='OpenFlow13')
        net.addLink(access, core)
        for hid in host_ids:
            h = net.addHost(f'h{hid}', ip=f'10.0.0.{hid}/24')
            net.addLink(h, access)
    try:
        net.start(); net.pingAll(); CLI(net)
    finally:
        net.stop()

setLogLevel('info')
run()
