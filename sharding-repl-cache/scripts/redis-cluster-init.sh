#!/bin/sh

sleep 10

echo "Creating Redis cluster..."

echo "yes" | redis-cli --cluster create \
  redis-master-1:6379 \
  redis-master-2:6381 \
  redis-master-3:6383 \
  redis-slave-1:6380 \
  redis-slave-2:6382 \
  redis-slave-3:6384 \
  --cluster-replicas 1

sleep 10

echo "Verifying Redis cluster..."
redis-cli -h redis-master-1 -p 6379 cluster info
redis-cli -h redis-master-2 -p 6381 cluster info
redis-cli -h redis-master-3 -p 6383 cluster info

echo "Redis cluster nodes:"
redis-cli -h redis-master-1 -p 6379 cluster nodes
redis-cli -h redis-master-2 -p 6381 cluster nodes
redis-cli -h redis-master-3 -p 6383 cluster nodes
echo "Done"
