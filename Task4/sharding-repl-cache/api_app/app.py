import json
import logging
import os
import time
from typing import List, Optional

import motor.motor_asyncio
from bson import ObjectId
from fastapi import Body, FastAPI, HTTPException, status
from fastapi_cache import FastAPICache
from fastapi_cache.backends.redis import RedisBackend
from logmiddleware import RouterLoggingMiddleware, logging_config
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from pydantic.functional_validators import BeforeValidator
from pymongo import errors
from redis import asyncio as aioredis
from redis.asyncio.cluster import RedisCluster as AsyncRedisCluster
from typing_extensions import Annotated

# Configure JSON logging
logging.config.dictConfig(logging_config)
logger = logging.getLogger(__name__)

app = FastAPI()
app.add_middleware(
    RouterLoggingMiddleware,
    logger=logger,
)

DATABASE_URL = os.environ["MONGODB_URL"]
DATABASE_NAME = os.environ["MONGODB_DATABASE_NAME"]
REDIS_URL = os.getenv("REDIS_URL", None)

# Track if cache is enabled
cache_enabled_flag = False


client = motor.motor_asyncio.AsyncIOMotorClient(DATABASE_URL)
db = client[DATABASE_NAME]

# Represents an ObjectId field in the database.
PyObjectId = Annotated[str, BeforeValidator(str)]


@app.on_event("startup")
async def startup():
    global cache_enabled_flag

    if REDIS_URL:
        try:
            # Parse Redis cluster nodes
            redis_url_clean = REDIS_URL.replace("redis://", "")
            hosts = redis_url_clean.split(",")

            if len(hosts) > 1:
                # Redis Cluster mode
                startup_nodes = []
                for host in hosts:
                    host_parts = host.split(":")
                    startup_nodes.append({
                        "host": host_parts[0],
                        "port": int(host_parts[1]) if len(host_parts) > 1 else 6379
                    })

                redis_client = AsyncRedisCluster(
                    startup_nodes=startup_nodes,
                    decode_responses=True,
                    skip_full_coverage_check=True
                )
            else:
                # Single Redis node
                host_parts = hosts[0].split(":")
                redis_client = aioredis.from_url(
                    f"redis://{hosts[0]}",
                    encoding="utf8",
                    decode_responses=True
                )

            # Test connection
            await redis_client.ping()
            FastAPICache.init(RedisBackend(redis_client), prefix="api:cache")
            cache_enabled_flag = True
            logger.info(f"Connected to Redis {'cluster' if len(hosts) > 1 else 'node'}")
        except Exception as e:
            logger.warning(f"Failed to connect to Redis: {e}")
            logger.warning("Application will continue without cache")
            cache_enabled_flag = False
    else:
        cache_enabled_flag = False


class UserModel(BaseModel):
    """
    Container for a single user record.
    """
    id: Optional[PyObjectId] = Field(alias="_id", default=None)
    age: int = Field(...)
    name: str = Field(...)


class UserCollection(BaseModel):
    """
    A container holding a list of `UserModel` instances.
    """
    users: List[UserModel]


@app.get("/")
async def root():
    collection_names = await db.list_collection_names()
    collections = {}
    for collection_name in collection_names:
        collection = db.get_collection(collection_name)
        collections[collection_name] = {
            "documents_count": await collection.count_documents({})
        }
    try:
        replica_status = await client.admin.command("replSetGetStatus")
        replica_status = json.dumps(replica_status, indent=2, default=str)
    except errors.OperationFailure:
        replica_status = "No Replicas"

    topology_description = client.topology_description
    read_preference = client.client_options.read_preference
    topology_type = topology_description.topology_type_name
    replicaset_name = topology_description.replica_set_name

    shards = None
    if topology_type == "Sharded":
        shards_list = await client.admin.command("listShards")
        shards = {}
        for shard in shards_list.get("shards", {}):
            shards[shard["_id"]] = shard["host"]

    return {
        "mongo_topology_type": topology_type,
        "mongo_replicaset_name": replicaset_name,
        "mongo_db": DATABASE_NAME,
        "read_preference": str(read_preference),
        "mongo_nodes": client.nodes,
        "mongo_primary_host": client.primary,
        "mongo_secondary_hosts": client.secondaries,
        "mongo_is_primary": client.is_primary,
        "mongo_is_mongos": client.is_mongos,
        "collections": collections,
        "shards": shards,
        "cache_enabled": cache_enabled_flag,
        "status": "OK",
    }


@app.get("/{collection_name}/count")
async def collection_count(collection_name: str):
    collection = db.get_collection(collection_name)
    items_count = await collection.count_documents({})
    return {"status": "OK", "mongo_db": DATABASE_NAME, "items_count": items_count}


@app.get(
    "/{collection_name}/users",
    response_description="List all users",
    response_model=UserCollection,
    response_model_by_alias=False,
)
async def list_users(collection_name: str):
    """
    List all of the user data in the database.
    """
    # Check if cache is enabled and use it
    if cache_enabled_flag:
        from fastapi_cache.decorator import cache

        @cache(expire=60)
        async def get_cached_users():
            time.sleep(1)
            collection = db.get_collection(collection_name)
            return UserCollection(users=await collection.find().to_list(1000))

        return await get_cached_users()
    else:
        # No cache, direct query
        time.sleep(1)
        collection = db.get_collection(collection_name)
        return UserCollection(users=await collection.find().to_list(1000))


@app.get(
    "/{collection_name}/users/{name}",
    response_description="Get a single user",
    response_model=UserModel,
    response_model_by_alias=False,
)
async def show_user(collection_name: str, name: str):
    """
    Get the record for a specific user, looked up by `name`.
    """
    collection = db.get_collection(collection_name)
    if (user := await collection.find_one({"name": name})) is not None:
        return user
    raise HTTPException(status_code=404, detail=f"User {name} not found")


@app.post(
    "/{collection_name}/users",
    response_description="Add new user",
    response_model=UserModel,
    status_code=status.HTTP_201_CREATED,
    response_model_by_alias=False,
)
async def create_user(collection_name: str, user: UserModel = Body(...)):
    """
    Insert a new user record.
    """
    collection = db.get_collection(collection_name)
    new_user = await collection.insert_one(
        user.model_dump(by_alias=True, exclude=["id"])
    )
    created_user = await collection.find_one({"_id": new_user.inserted_id})
    return created_user