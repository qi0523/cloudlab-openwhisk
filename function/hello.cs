# requirements

wget https://dot.net/v1/dotnet-install.sh
sudo chmod +x ./dotnet-install.sh
./dotnet-install.sh --version 3.1


dotnet new classlib -n Apache.OpenWhisk.Example.Dotnet -lang "C#"
cd Apache.OpenWhisk.Example.Dotnet
dotnet add package Newtonsoft.Json -v 12.0.1

using System;
using Newtonsoft.Json.Linq;

namespace Apache.OpenWhisk.Example.Dotnet
{
    public class Hello
    {
        public JObject Main(JObject args)
        {
            string name = "stranger";
            if (args.ContainsKey("name")) {
                name = args["name"].ToString();
            }
            JObject message = new JObject();
            message.Add("greeting", new JValue($"Hello, {name}!"));
            return (message);
        }
    }
}

dotnet publish -c Release -o out
cd out
zip -r -0 helloDotNet.zip *

wsk action update helloDotNet helloDotNet.zip --main Apache.OpenWhisk.Example.Dotnet::Apache.OpenWhisk.Example.Dotnet.Hello::Main --kind dotnet:3.1