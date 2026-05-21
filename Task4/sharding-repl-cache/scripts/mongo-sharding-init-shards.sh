#!/bin/sh

echo "\nInitializing Shards..."
echo "\nShard 1"

mongosh --host shard1-master:27022 <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-master:27022" },
    { _id: 1, host: "shard1-replica1:27024" },
    { _id: 2, host: "shard1-replica2:27025" },
    { _id: 3, host: "shard1-replica3:27026" }
  ]
})
EOF

echo "\nShard 2"

mongosh --host shard2-master:27023 <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-master:27023" },
    { _id: 1, host: "shard2-replica1:27027" },
    { _id: 2, host: "shard2-replica2:27028" },
    { _id: 3, host: "shard2-replica3:27029" }
  ]
})
EOF

echo "\nDone."

sleep 10

echo "\nInitializing Routers..."

mongosh --host router1:27020 <<EOF
sh.addShard("shard1/shard1-master:27022,shard1-replica1:27024,shard1-replica2:27025,shard1-replica3:27026")
sh.addShard("shard2/shard2-master:27023,shard2-replica1:27027,shard2-replica2:27028,shard2-replica3:27029")
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

echo "\nShard 1 (master):"
mongosh --host shard1-master:27022 --quiet <<EOF
use somedb;
print("Count: " + db.helloDoc.countDocuments());
EOF

echo "\nShard 1 (replica1):"
mongosh --host shard1-replica1:27024 --quiet <<EOF
use somedb;
print("Count: " + db.helloDoc.countDocuments());
EOF

echo "\nShard 1 (replica2):"
mongosh --host shard1-replica2:27025 --quiet <<EOF
use somedb;
print("Count: " + db.helloDoc.countDocuments());
EOF

echo "\nShard 1 (replica3):"
mongosh --host shard1-replica3:27026 --quiet <<EOF
use somedb;
print("Count: " + db.helloDoc.countDocuments());
EOF

echo "\nShard 2 (master):"
mongosh --host shard2-master:27023 --quiet <<EOF
use somedb;
print("Count: " + db.helloDoc.countDocuments());
EOF

echo "\nShard 2 (replica1):"
mongosh --host shard2-replica1:27027 --quiet <<EOF
use somedb;
print("Count: " + db.helloDoc.countDocuments());
EOF

echo "\nShard 2 (replica2):"
mongosh --host shard2-replica2:27028 --quiet <<EOF
use somedb;
print("Count: " + db.helloDoc.countDocuments());
EOF

echo "\nShard 2 (replica3):"
mongosh --host shard2-replica3:27029 --quiet <<EOF
use somedb;
print("Count: " + db.helloDoc.countDocuments());
EOF

echo "\nDone."
echo "\nAll Complete."
