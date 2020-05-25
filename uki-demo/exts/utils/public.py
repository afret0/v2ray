def cmp(x, y):
    """
    cmp(x, y) -> integer

    Return negative if x<y, zero if x==y, positive if x>y.
    """
    if x < y:
        return -1
    elif x == y:
        return 0
    else:
        return 1


async def get_remark(user_id, another_id, redis, config):
    """
    查询user_id对another_id缓存中的备注
    :param user_id:
    :param another_id:
    :param redis:
    :param config:
    :return:
    """
    result = cmp(str(user_id), str(another_id))
    if result == 1:
        relation_key = config.RELATIONSHIP_USERS.format(another_id, user_id)
        cache_result = await redis.get(relation_key, encoding=None)
        if not cache_result:
            return ""
        result = cache_result[40:]
    else:
        relation_key = config.RELATIONSHIP_USERS.format(user_id, another_id)
        cache_result = await redis.get(relation_key, encoding=None)
        if not cache_result:
            return ""
        result = cache_result[1:39]

    return result.replace(b'\u0000', b'').replace(b'\\x00', b'').replace(b'\x00', b'').decode('utf-8')
