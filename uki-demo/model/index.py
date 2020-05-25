from pymongo import ASCENDING, IndexModel


class DemoIndexes(object):
    # IndexModel
    # name: custom name to use for this index - if none is given, a name will be generated.
    # unique: if True creates a uniqueness constraint on the index.
    # background: if True this index should be created in the background.
    # sparse: if True, omit from the index any documents that lack the indexed field.
    ukiId = IndexModel([("ukiId", ASCENDING)], background=True)


async def check_index(mongo, collection_index=None):
    """
    检查表索引是否被创建
    :param mongo:
    :param collection_index: {表名: 表索引}
    :return:
    """
    if collection_index is None:
        collection_index = {"demo": DemoIndexes}

    for collection, index_model in collection_index.items():
        index_keys = [index['key'] async for index in
                      mongo[collection].list_indexes()]
        # [SON([('_id', 1)]), SON([('_id', 1)]), SON([('_id', 1)]), ...]
        for item in index_model.__dict__.values():
            if not isinstance(item, IndexModel):
                continue
            if item.document['key'] not in index_keys:
                await create_indexes(mongo, collection, index_model)
                break


async def create_indexes(mongo, collection, index_model):
    """
    创建表索引
    :param mongo:
    :param collection: 表名
    :param index_model: 表索引
    :return:
    """
    await mongo[collection].create_indexes(
        [index for index in index_model.__dict__.values() if
         isinstance(index, IndexModel)])
