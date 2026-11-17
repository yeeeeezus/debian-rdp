from mininet.net import Mininet
from mininet.node import RemoteController, OVSSwitch
from mininet.cli import CLI
from mininet.log import setLogLevel
from mininet.link import TCLink
import statistics, re

def create_network():
    net = Mininet(controller=None, switch=OVSSwitch, link=TCLink)
    net.addController('c0', controller=RemoteController,
                     ip='127.0.0.1', port=6653)
    for i in range(1, 5):                    # h4 is the web server
        net.addHost(f'h{i}', ip=f'10.0.0.{i}/24')
    s1 = net.addSwitch('s1', protocols='OpenFlow13')
    for i in range(1, 5):
        net.addLink(net.get(f'h{i}'), s1)
    net.start()
    return net

def warm_up(net, count=3):
    # 3 pings before measuring: first connection pays for ARP discovery
    # and OpenFlow rule installation, later measurements are cleaner.
    for _ in range(count):
        net.get('h1').cmd('ping -c 1 -W 1 10.0.0.4 >/dev/null 2>&1')

def measure_rtt(net, count=10):
    out = net.get('h1').cmd(f'ping -c {count} -W 1 10.0.0.4')
    rtts = [float(x) for x in re.findall(r'time=([\d.]+)', out)]
    sent = received = 0
    m = re.search(r'(\d+) packets transmitted, (\d+) received', out)
    if m:
        sent, received = map(int, m.groups())
    return {'rtts': rtts, 'min': min(rtts), 'avg': statistics.mean(rtts),
            'max': max(rtts), 'sent': sent, 'received': received}

def main():
    net = create_network()
    try:
        warm_up(net)
        r = measure_rtt(net)
        print('RTT min/avg/max =', round(r['min'], 2),
              round(r['avg'], 2), round(r['max'], 2), '(ms)')
        print('sent/received =', r['sent'], r['received'])
        CLI(net)
    finally:
        net.stop()

setLogLevel('info')
main()
