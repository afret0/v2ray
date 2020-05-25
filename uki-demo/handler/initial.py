from sanic import response
import time


async def ping(request):
    """
    用于心跳监测
    :param request:
    :return:
    """
    # redis = request.app.redis
    #
    # redis_ping = await redis.ping()
    # assert redis_ping == "PONG"

    return response.json({"code": 0, "message": "pong"})

async def demo(request):
    time.sleep(1)
    return response.json({"code": 0, "message": "pong"})