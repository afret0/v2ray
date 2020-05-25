import os

import sentry_sdk
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from blueprints import v1
from config import config
from exts.db import mongo, redis
from exts.utils.discovery import query_config
from model import index
from neoclub import AioMongoClientCache, DramatiqBroker
from sanic import Sanic
from sanic.log import LOGGING_CONFIG_DEFAULTS
from sentry_sdk.integrations.sanic import SanicIntegration
import time

LOGGING_CONFIG_DEFAULTS['formatters']['generic'][
    'format'] = "%(asctime)s [%(process)d] [%(levelname)s] [%(filename)s: %(funcName)s: %(lineno)d] %(message)s"
app = Sanic("uki-demo", log_config=LOGGING_CONFIG_DEFAULTS)

# 基于环境参数加载对应配置文件
app.config.from_object(config)
# 注册blueprint
app.blueprint(v1.blueprint)


@app.listener('before_server_start')
async def setup_db(app, loop):
    # # 初始化mongo连接池
    # app.mongo = mongo.creating_client().uki
    # # 初始化mongoCache连接池
    # app.mongo_cache = AioMongoClientCache().uki
    # # 初始化redis连接池
    # app.redis = await redis.create_pool(0, loop, app.config)
    # # 初始化redis-cache连接池
    # app.redis_cache = await redis.create_cache_pool(2, loop, app.config)
    # # 初始化dramatiq broker
    # app.broker = DramatiqBroker()
    # app.broker_node = DramatiqBroker(vhost='node')
    # # sentry错误收集
    # app.sentry = sentry_sdk.init(dsn=app.config.SENTRY_DSN, integrations=[SanicIntegration()],
    #                              environment=os.environ['ENV'], attach_stacktrace=True)
    # # 检查mongo索引
    # await index.check_index(mongo.creating_client().uki)
    await query_config(app)
    # print(time.time())
    # time.sleep(3)
    # print(time.time())



@app.listener('after_server_start')
async def notify_server_started(app, loop):
    # 定时任务
    # scheduler = AsyncIOScheduler()
    # scheduler.add_job(query_config, 'interval', seconds=10, args=[app])
    # scheduler.start()
    pass


# @app.listener('before_server_stop')
# async def notify_server_stopping(app, loop):
#     pass


# @app.listener('after_server_stop')
# async def close_db(app, loop):
#     app.redis.close()
#     app.redis_cache.close()
#     await app.redis.wait_closed()
#     await app.redis_cache.wait_closed()


if __name__ == "__main__":
    time.sleep(2)
    app.run(host=app.config.HOST, port=app.config.PORT, debug=app.config.DEBUG, access_log=app.config.ACCESS_LOG,backlog=2)
