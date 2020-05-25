import aioredis


async def create_pool(db, loop, conf):
    return await aioredis.create_redis(
        conf.REDIS_ADDRESS,
        db=db,
        encoding='utf-8',
        loop=loop)


async def create_cache_pool(db, loop, conf):
    return await aioredis.create_redis(
        "redis://" + conf.REDIS_CACHE_HOST,
        db=db,
        encoding='utf-8',
        loop=loop)
