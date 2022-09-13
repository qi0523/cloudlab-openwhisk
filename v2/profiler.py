""" Ubuntu 20.04 Optional Kubernetes Cluster w/ OpenWhisk optionally deployed with a parameterized
number of nodes.

Instructions:
Note: It can take upwards of 15 min. for the cluster to fully initialize. Thank you for your patience!
For full documentation, see the GitHub repo: https://github.com/qi0523/cloudlab-openwhisk
Output from the startup script is found at /home/openwhisk-kubernetes/start.log on all nodes
"""

# Import the Portal object.
import geni.portal as portal
# Import the ProtoGENI library.
import geni.rspec.pg as rspec

BASE_IP = "10.10.1"
BANDWIDTH = 10000000
IMAGE = 'urn:publicid:IDN+clemson.cloudlab.us+image+containernetwork-PG0:containerd-k8s'

pc = portal.Context()
pc.defineParameter("nodeCount", 
                   "Number of nodes in the experiment. It is recommended that at least 3 be used.",
                   portal.ParameterType.INTEGER, 
                   3)

params = pc.bindParameters()

pc.verifyParameters()
request = pc.makeRequestRSpec()

def create_node(name, nodes, interfaces):
  # Create node
  node = request.XenVM(name)
  node.exclusive = True
  node.cores = 2
  # Ask for 2GB of ram
  node.ram   = 4096
  node.disk_image = IMAGE
  
  # Add interface
  iface = node.addInterface("if1")
  iface.addAddress(rspec.IPv4Address("{}.{}".format(BASE_IP, 1 + len(nodes)), "255.255.255.0"))
  interfaces.append(iface)
  # Add to node list
  nodes.append(node)

nodes = []
interfaces = []

for i in range(params.nodeCount):
    name = "ow"+str(i+1)
    create_node(name, nodes, interfaces)

for i in range(params.nodeCount):
    for j in range(i+1, params.nodeCount):
        link = request.Link("ow"+str(i+1)+"_ow"+str(j+1))
        link.addInterface(interfaces[i])
        link.addInterface(interfaces[j])
        if i==0:
            link.bandwidth=40000000
        else:
            link.bandwidth=BANDWIDTH

pc.printRequestRSpec()