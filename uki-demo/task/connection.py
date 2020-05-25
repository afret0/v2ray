import redis
from config import config
from neoclub import MongoClientCache, DramatiqBroker
from pymongo import MongoClient


class ConnectionInit(object):
    abstract = True
    _mongo = None
    _mongo_cache = None
    _redis = {}
    _redis_rel = {}
    _redis_delay = {}
    _redis_cache = {}
    _broker = None
    _broker_node = None

    @property
    def mongo(self):
        if ConnectionInit._mongo is None:
            _mc = MongoClient(config.MONGO_REPLICA, maxPoolSize=8)
            ConnectionInit._mongo = _mc['uki']
        return ConnectionInit._mongo

    @property
    def mongo_cache(self):
        if ConnectionInit._mongo_cache is None:
            ConnectionInit._mongo_cache = MongoClientCache().uki
        return ConnectionInit._mongo_cache

    def redis(self, db=0):
        if ConnectionInit._redis.get(db) is None:
            ConnectionInit._redis[db] = redis.StrictRedis.from_url(config.REDIS_ADDRESS,
                                                                   db=db, charset="utf-8",
                                                                   decode_responses=True)
        return ConnectionInit._redis.get(db)

    def redis_rel(self, db=0):
        if ConnectionInit._redis_rel.get(db) is None:
            ConnectionInit._redis_rel[db] = redis.from_url(config.REDIS_REL_ADDRESS,
                                                           db=db, charset="utf-8",
                                                           decode_responses=True)
        return ConnectionInit._redis_rel.get(db)

    def redis_delay(self, db=0):
        if ConnectionInit._redis_delay.get(db) is None:
            ConnectionInit._redis_delay[db] = redis.StrictRedis.from_url(config.REDIS_DELAY_ADDRESS,
                                                                         db=db, charset="utf-8",
                                                                         decode_responses=True)
        return ConnectionInit._redis_delay.get(db)

    def redis_cache(self, db=0):
        if ConnectionInit._redis_cache.get(db) is None:
            ConnectionInit._redis_cache[db] = redis.StrictRedis.from_url("redis://" + config.REDIS_CACHE_HOST,
                                                                         db=db, charset="utf-8",
                                                                         decode_responses=True)
        return ConnectionInit._redis_cache.get(db)

    @property
    def broker(self):
        if self._broker is None:
            self._broker = DramatiqBroker()
        return self._broker

    @property
    def broker_node(self):
        if self._broker_node is None:
            self._broker_node = DramatiqBroker(vhost='node')
        return self._broker_node
