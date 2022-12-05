# Import the Portal object.
import geni.portal as portal
# Import the ProtoGENI library.
import geni.rspec.pg as rspec

IMAGE1 = 'urn:publicid:IDN+clemson.cloudlab.us+image+containernetwork-PG0:owv1'
IMAGE2 = 'urn:publicid:IDN+clemson.cloudlab.us+image+containernetwork-PG0:registry'

pc = portal.Context()

pc.defineParameter("controller_cores",
                   "Controller cpu cores",
                   portal.ParameterType.INTEGER,
                   6,
                   longDescription="Controller cpu cores.")

pc.defineParameter("controller_memory",
                   "Controller memory",
                   portal.ParameterType.INTEGER,
                   32768,
                   longDescription="Controller memory.")

pc.defineParameter("tempFileSystemSize", 
                   "Temporary Filesystem Size",
                   portal.ParameterType.INTEGER, 
                   0,
                   advanced=True,
                   longDescription="The size in GB of a temporary file system to mount on each of your " +
                   "nodes. Temporary means that they are deleted when your experiment is terminated. " +
                   "The images provided by the system have small root partitions, so use this option " +
                   "if you expect you will need more space to build your software packages or store " +
                   "temporary files. 0 GB indicates maximum size.")

pc.defineParameter("registry_cores",
                   "Registry cpu cores",
                   portal.ParameterType.INTEGER,
                   12,
                   longDescription="Registry cpu cores.")

pc.defineParameter("registry_memory",
                   "Registry memory",
                   portal.ParameterType.INTEGER,
                   65536,
                   longDescription="Registry memory.")

params = pc.bindParameters()

pc.verifyParameters()

request = pc.makeRequestRSpec()

node1 = request.XenVM("master")

node1.exclusive = True
  
node1.cores = params.controller_cores
  # Ask for 2GB of ram
node1.ram = params.controller_memory

node1.disk_image = IMAGE1

# Add extra storage space
if (params.tempFileSystemSize > 0):
    bs = node1.Blockstore("master-bs", "/mydata")
    bs.size = str(params.tempFileSystemSize) + "GB"
    bs.placement = "any"

node2 = request.XenVM("registry")

node2.exclusive = True
  
node2.cores = params.registry_cores
  # Ask for 2GB of ram
node2.ram = params.registry_memory

node2.disk_image = IMAGE2

#node.addService(rspec.Execute(shell="bash", command="/local/repository/start.sh {} > /home/cloudlab-openwhisk/start.log 2>&1 &".format(params.numInvokers)))
# ./start.sh 1 "false" > /home/cloudlab-openwhisk/start.log 2>&1
# bash ./st.sh 2 "true" > /home/cloudlab-openwhisk/start.log 2>&1
pc.printRequestRSpec()