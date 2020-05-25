'''
-------------------------------------------------
    Author :        Afreto
    E-mail:         kongandmarx@163.com
-------------------------------------------------
    Description : 
    Usage: 
-------------------------------------------------
'''

import requests

# url = "http://uki:Neoclub2018@localhost:15672/api/overview"
url = "http://uki:Neoclub2018@192.168.3.3:15672/api/overview"

payload = {}
headers= {}

response = requests.request("GET", url, headers=headers, data = payload)

print(response)