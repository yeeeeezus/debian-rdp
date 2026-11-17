from mininet.net import Mininet
from mininet.node import RemoteController, OVSSwitch
from mininet.cli import CLI
from mininet.log import setLogLevel
import json

def create_network():
    net = Mininet(controller=None, switch=OVSSwitch)
    net.addController('c0', controller=RemoteController,
                     ip='127.0.0.1', port=6653)
    for i in range(1, 5):
        net.addHost(f'h{i}', ip=f'10.0.0.{i}/24')
    s1 = net.addSwitch('s1', protocols='OpenFlow13')
    for i in range(1, 5):
        net.addLink(net.get(f'h{i}'), s1)
    net.start()
    return net

def measure_throughput(net, seconds=10):
    h1, h4 = net.get('h1'), net.get('h4')
    server = h4.popen(['iperf3', '-s', '-p', '5201'],
                      stdout=-1, stderr=-1)
    client = h1.popen(['iperf3', '-c', '10.0.0.4', '-p', '5201',
                       '-t', str(seconds), '-J'],
                      stdout=-1, stderr=-1)
    stdout, stderr = client.communicate(timeout=seconds + 20)
    server.terminate()
    if client.returncode != 0:
        raise RuntimeError('iperf3 client failed: '
                           + stderr.decode(errors='replace'))
    data = json.loads(stdout.decode())
    if 'error' in data:
        raise RuntimeError('iperf3: ' + data['error'])
    mbps = data['end']['sum_received']['bits_per_second'] / 1_000_000
    return mbps

def main():
    net = create_network()
    try:
        mbps = measure_throughput(net, seconds=10)
        print('Throughput =', round(mbps, 2), 'Mbps')
        CLI(net)
    finally:
        net.stop()

setLogLevel('info')
main()
