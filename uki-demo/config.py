import os
from typing import Type, Union


class BaseConfig(object):
    HOST = "0.0.0.0"
    PORT = "20099"
    DEBUG = True
    ACCESS_LOG = True
    SERVER_NAME = "uki-demo"
    QUEUE_NAME = "actor-demo"

    MAP_USER_HIMSELF_FIELDS = "_id,ukiId,name,sex,wantSex,phone,city,birth,starSign,tag,signature,registeredAt,avatarUrl,block,risk,forbid,ucoin,giftCount,giftAmount,password,account.accid"
    MAP_OTHER_USER_FIELDS = "_id,ukiId,name,sex,city,birth,starSign,tag,signature,avatarUrl,block,risk,giftCount,giftAmount"


class LocConfig(BaseConfig):
    ENV = 'loc'

    MONGO_REPLICA = "mongodb://192.168.3.3:27017"

    REDIS_ADDRESS = "redis://192.168.3.3"
    REDIS_REL_ADDRESS = "redis://192.168.3.3"
    REDIS_DELAY_ADDRESS = "redis://192.168.3.3"
    REDIS_CACHE_HOST = "192.168.3.3"
    REDIS_HOST = "192.168.3.3"

    RABBITMQ_URL = "amqp://uki:Neoclub2018@192.168.3.3:5672/"

    SENTRY_DSN = ''
    CONSUL_URL = 'http://192.168.3.3:8500/v1/kv/dev/uki-demo?raw'


class DevConfig(BaseConfig):
    ENV = 'dev'

    MONGO_REPLICA = "mongodb://127.0.0.1:27017"

    REDIS_ADDRESS = "redis://127.0.0.1"
    REDIS_HOST = "127.0.0.1"
    REDIS_PASSWORD = 'Neoclub2018'
    REDIS_REL_ADDRESS = "redis://localhost"
    REDIS_DELAY_ADDRESS = "redis://localhost"
    REDIS_CACHE_HOST = "127.0.0.1"

    RABBITMQ_URL = "amqp://uki:Neoclub2018@127.0.0.1:5672/"

    SENTRY_DSN = ''
    CONSUL_URL = 'http://localhost:8500/v1/kv/dev/uki-demo?raw'


class ProConfig(BaseConfig):
    ENV = 'pro'
    DEBUG = False
    LOG_LEVEL = 'INFO'

    MONGO_REPLICA = "mongodb://root:Neoclub2018@dds-bp1fdc32bfa36a841.mongodb.rds.aliyuncs.com:3717,dds-bp1fdc32bfa36a842.mongodb.rds.aliyuncs.com:3717,dds-bp1fdc32bfa36a843.mongodb.rds.aliyuncs.com:3717,dds-bp1fdc32bfa36a844.mongodb.rds.aliyuncs.com:3717/admin?replicaSet=mgset-10457077&readPreference=secondaryPreferred"

    REDIS_ADDRESS = "redis://r-bp1bce4fcac1c3e4.redis.rds.aliyuncs.com"
    REDIS_HOST = "r-bp1bce4fcac1c3e4.redis.rds.aliyuncs.com"
    REDIS_PASSWORD = 'Neoclub2018'
    REDIS_REL_ADDRESS = "redis://redis.uki.im"
    REDIS_DELAY_ADDRESS = "redis://delay.uki.im"
    REDIS_CACHE_HOST = "r-bp1620e1cfc23824.redis.rds.aliyuncs.com"

    RABBITMQ_URL = "amqp://uki:Neoclub2018@rmq.uki.im:5672/"

    SENTRY_DSN = ''
    CONSUL_URL = 'http://consul.uki.im/v1/kv/pro/uki-demo?raw'


CONFIG_DICT = {"loc": LocConfig, "dev": DevConfig, "pro": ProConfig}

config: Type[Union[LocConfig, DevConfig, ProConfig]] = CONFIG_DICT[os.environ["ENV"]]
