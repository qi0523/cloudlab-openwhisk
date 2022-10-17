# Import the Portal object.
import geni.portal as portal
# Import the ProtoGENI library.
import geni.rspec.pg as rspec

IMAGE = 'urn:publicid:IDN+clemson.cloudlab.us+image+containernetwork-PG0:containerdv2-k8s'

pc = portal.Context()

pc.defineParameter("cores",
                   "Master cpu cores",
                   portal.ParameterType.INTEGER,
                   2,
                   longDescription="Master cpu cores.")

pc.defineParameter("memory",
                   "Master memory",
                   portal.ParameterType.INTEGER,
                   4096,
                   longDescription="Master memory.")

pc.defineParameter("deployOpenWhisk",
                   "Deploy OpenWhisk",
                   portal.ParameterType.BOOLEAN,
                   True,
                   longDescription="Use helm to deploy OpenWhisk.")

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

pc.defineParameter("numInvokers",
                   "Number of Invokers",
                   portal.ParameterType.INTEGER,
                   1,
                   advanced=True,
                   longDescription="Number of OpenWhisk invokers set in the mycluster.yaml file, and number of nodes labelled as Openwhisk invokers. " \
                           "All nodes which are not invokers will be labelled as OpenWhisk core nodes.")

params = pc.bindParameters()

pc.verifyParameters()

request = pc.makeRequestRSpec()

node = request.XenVM("master")

node.exclusive = True
  
node.cores = params.cores
  # Ask for 2GB of ram
node.ram   = params.memory

node.disk_image = IMAGE

# Add extra storage space
bs = node.Blockstore(name + "-bs", "/mydata")
bs.size = str(params.tempFileSystemSize) + "GB"
bs.placement = "any"

#node.addService(rspec.Execute(shell="bash", command="/local/repository/start.sh {} > /home/cloudlab-openwhisk/start.log 2>&1 &".format(params.numInvokers)))
# ./start.sh 1 "false" > /home/cloudlab-openwhisk/start.log 2>&1
# bash ./st.sh 2 "true" > /home/cloudlab-openwhisk/start.log 2>&1
pc.printRequestRSpec()