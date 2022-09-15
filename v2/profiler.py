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

pc = portal.Context()
pc.defineParameter("nodeCount", 
                   "Number of nodes in the experiment. It is recommended that at least 3 be used.",
                   portal.ParameterType.INTEGER, 
                   3)

params = pc.bindParameters()

pc.verifyParameters()
request = pc.makeRequestRSpec()

router = request.XenVM("router")

def create_node(name, nodes):
  # Create node
  node = request.XenVM(name)
  node.exclusive = True
  node.cores = 2
  # Ask for 4GB of ram
  node.ram   = 4096
  # Add to node list
  nodes.append(node)

nodes = []

for i in range(params.nodeCount):
    name = "node"+str(i+1)
    create_node(name, nodes)

for i in range(params.nodeCount):
    link = request.Link("node"+str(i+1),"", (nodes[i], router))
    if i==0:
        link.bandwidth=40000000 # 40Gbps
    else:
        link.bandwidth=10000000 # 1Gbps

pc.printRequestRSpec()