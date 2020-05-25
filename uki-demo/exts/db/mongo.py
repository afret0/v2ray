from config import config
from motor import motor_asyncio


def creating_client(maxPoolSize=10, **kwargs):
    """
    在服务启动时创建一个mongo客户端
    :return:
    """
    # 一个AsyncIOMotorClient实例可以支持多个独立的databases。
    return motor_asyncio.AsyncIOMotorClient(config.MONGO_REPLICA, maxPoolSize=maxPoolSize, **kwargs)
