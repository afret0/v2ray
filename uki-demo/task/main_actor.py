import os

import dramatiq
import sentry_sdk
from config import config
from dramatiq.brokers.rabbitmq import RabbitmqBroker
from dramatiq.rate_limits import BucketRateLimiter
from dramatiq.rate_limits.backends import RedisBackend
from task.connection import ConnectionInit

broker = RabbitmqBroker(confirm_delivery=True, url=config.RABBITMQ_URL)
raven_client = sentry_sdk.init(dsn=config.SENTRY_DSN, environment=os.environ['ENV'], attach_stacktrace=True)
dramatiq.set_broker(broker)


# Create your views here.


class SentryMiddleware(dramatiq.Middleware):
    def __init__(self, raven_client):
        self.raven_client = raven_client

    def after_process_message(self, broker, message, *, result=None, exception=None):
        if exception is not None:
            self.raven_client.captureException()


broker.add_middleware(SentryMiddleware(raven_client))


class MainInit(ConnectionInit):

    def __init__(self):
        self._backend = RedisBackend(client=self.redis)
        self._mutex_limit = {}

    @property
    def redis(self):
        return super().redis(0)

    @property
    def redis_rel(self):
        return super().redis_rel(0)

    @property
    def redis_delay(self):
        return super().redis_delay(0)

    def mutex_limit(self, name, rate, ttl=None):
        """
        :param name: The key to rate limit on.
        :param rate: The maximum number of concurrent operations per key.
        :param ttl: The time in seconds that keys may live for.
        :return:
        """
        if self._mutex_limit.get(name) is None:
            name = "distributed-mutex:" + name
            if not ttl:
                ttl = 1_000
            self._mutex_limit[name] = BucketRateLimiter(self._backend, name, limit=rate, bucket=ttl)
        return self._mutex_limit[name]


conn = MainInit()
