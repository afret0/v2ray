from handler.initial import ping, demo
from sanic import Blueprint

# 控制接口版本
blueprint = Blueprint('v1', url_prefix='/v1')

# 注册route
blueprint.add_route(ping, '/ping', methods=['GET'])
blueprint.add_route(demo, '/demo')
