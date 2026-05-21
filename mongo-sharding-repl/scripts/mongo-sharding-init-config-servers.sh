#!/bin/sh

sleep 15

echo "Initializing Config Servers..."

mongosh --host configSrv1:27017 <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27017" },
    { _id: 1, host: "configSrv2:27018" },
    { _id: 2, host: "configSrv3:27019" }
  ]
})
EOF

echo "Done."

sleep 10
