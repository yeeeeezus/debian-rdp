from mininet.net import Mininet
from mininet.node import RemoteController, OVSSwitch
from mininet.cli import CLI
from mininet.log import setLogLevel
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--switches', type=int, default=3)   # number of switches
parser.add_argument('--hosts', type=int, default=2)       # hosts per switch
args = parser.parse_args()

if (args.switches < 1 or args.hosts < 1
        or args.switches * args.hosts > 254):
    parser.error('Positive counts required; maximum 254 hosts')

def run():
    net = Mininet(controller=None, switch=OVSSwitch)
    net.addController('c0', controller=RemoteController,
                     ip='127.0.0.1', port=6653)
    switches = []
    for s in range(1, args.switches+1):
        sw = net.addSwitch(f's{s}', protocols='OpenFlow13')
        switches.append(sw)
    hid = 0
    for s in range(args.switches):
        for _ in range(args.hosts):
            hid += 1
            h = net.addHost(f'h{hid}', ip=f'10.0.0.{hid}/24')
            net.addLink(h, switches[s])
    for i in range(len(switches)-1):
        net.addLink(switches[i], switches[i+1])
    try:
        net.start(); net.pingAll(); CLI(net)
    finally:
        net.stop()

setLogLevel('info')
run()
