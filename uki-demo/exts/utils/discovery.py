import asyncio

from neoclub import aiorequest
from sanic.log import logger


async def query_config(app):
    # headers, resp = await aiorequest.get(app.config.CONSUL_URL,
    #                                      timeout=1,
    #                                      resp_headers=True,
    #                                      exception=asyncio.TimeoutError,
    #                                      resp_default=[{"X-Consul-Index": 0}, {}])
    #
    # consul_index = int(headers['X-Consul-Index'])
    # if consul_index > app.config.get('X-Consul-Index', -1):
    #     resp['X-Consul-Index'] = consul_index
    #     app.config.update(resp)
    #     logger.info(resp)

    return
