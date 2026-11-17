from mininet.net import Mininet
from mininet.node import RemoteController, OVSSwitch
from mininet.cli import CLI
from mininet.log import setLogLevel

def run():
    net = Mininet(controller=None, switch=OVSSwitch)
    net.addController('c0', controller=RemoteController,
                     ip='127.0.0.1', port=6653)
    h1 = net.addHost('h1', ip='10.0.0.1/24')
    h2 = net.addHost('h2', ip='10.0.0.2/24')
    s1 = net.addSwitch('s1', protocols='OpenFlow13')
    net.addLink(h1, s1)
    net.addLink(h2, s1)
    try:
        net.start()
        print('--- link UP ---')
        print(h1.cmd('ping -c 2 -W 1 10.0.0.2'))
        net.configLinkStatus('s1', 'h1', 'down')
        print('--- link s1-h1 DOWN ---')
        print(h1.cmd('ping -c 2 -W 1 10.0.0.2'))
        net.configLinkStatus('s1', 'h1', 'up')
        print('--- link restored ---')
        print(h1.cmd('ping -c 2 -W 1 10.0.0.2'))
        CLI(net)
    finally:
        net.stop()

setLogLevel('info')
run()
