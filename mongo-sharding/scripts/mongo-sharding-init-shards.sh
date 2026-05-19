#!/bin/sh

echo "\nInitializing Shards..."

mongosh --host shard1:27022 <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1:27022" }
  ]
})
EOF

mongosh --host shard2:27023 <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2:27023" }
  ]
})
EOF

echo "\nDone."

sleep 10

echo "\nInitializing Routers..."

mongosh --host router1:27020 <<EOF
sh.addShard("shard1/shard1:27022")
sh.addShard("shard2/shard2:27023")
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" })
EOF

echo "\nDone."
echo "\nInitializing Data..."

mongosh --host router1:27020 <<EOF
use somedb;
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i});
EOF

echo "\nDone."

sleep 10

echo "\nVerifying Sharding..."
echo "\nRouter 1:"
mongosh --host router1:27020 --quiet <<EOF
use somedb;
print("Count: " + db.helloDoc.countDocuments());
EOF

echo "\nRouter 2:"
mongosh --host router2:27021 --quiet <<EOF
use somedb;
print("Count: " + db.helloDoc.countDocuments());
EOF

echo "\nShard 1:"
mongosh --host shard1:27022 --quiet <<EOF
use somedb;
print("Count: " + db.helloDoc.countDocuments());
EOF

echo "\nShard 2:"
mongosh --host shard2:27023 --quiet <<EOF
use somedb;
print("Count: " + db.helloDoc.countDocuments());
EOF

echo "\nDone."
echo "\nAll Complete."
