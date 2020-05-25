'''
-------------------------------------------------
    Author :        Afreto
    E-mail:         kongandmarx@163.com
-------------------------------------------------
    Description : 
    Usage: 
-------------------------------------------------
'''
import time

from prometheus_client import start_http_server
from prometheus_client.core import GaugeMetricFamily, REGISTRY
import requests




class OverviewCollector(object):
    def collect(self):
        print("collecting...")
        metric = GaugeMetricFamily(name="queue_totals", documentation="message_ready",
                                   labels=["msg_type"])

        payload = {}
        headers = {}

        # url = "http://uki:Neoclub2018@127.0.0.1:15672/api/overview"
        # response = requests.get(url=url)
        # data = response.json()
        queue_totals = data.get("queue_totals", {})
        msg_ready = queue_totals.get("messages_ready", 0)
        msg = queue_totals.get("messages", 0)
        msg_unacknowledged = queue_totals.get(
            "messages_unacknowledged", 0)

        metric.add_metric(["msg_ready"], msg_ready)
        metric.add_metric(["msg"], msg)
        metric.add_metric(["msg_unacknowledged"], msg_unacknowledged)

        yield metric


app_dispatch = DispatcherMiddleware(app, {
    '/metrics': make_wsgi_app()
})

if __name__ == "__main__":
    REGISTRY.register(OverviewCollector())
    # app.run(host="0.0.0.0", port=10111, debug=True)
    start_http_server(10111)
    print("start...")
    while True:
        time.sleep(1)
