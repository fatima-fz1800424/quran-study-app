import urllib.parse
import urllib.request

url = 'https://tanzil.net/trans/?transID=en.yusufali&type=txt'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
with urllib.request.urlopen(req, timeout=30) as r:
    data = r.read().decode('utf-8', 'replace')

print(data[:1200])
print('---COUNT---')
print(len(data.splitlines()))
