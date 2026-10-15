#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
"""Create neutral non-payment build resources; no QR/account content."""
from pathlib import Path
import struct,zlib
root=Path(__file__).resolve().parents[1]/'RightDisplay/Resources/Sponsor'
def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
n=256;scan=[]
for y in range(n):
 row=bytearray()
 for x in range(n):
  cross=abs(x-y)<3 or abs(x+y-(n-1))<3
  row.extend((170,175,182,255) if cross else (238,240,243,255))
 scan.append(b'\0'+bytes(row))
data=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',n,n,8,6,0,0,0))+chunk(b'tEXt',b'Description\0Non-payment placeholder; no QR or account data')+chunk(b'IDAT',zlib.compress(b''.join(scan),9))+chunk(b'IEND',b'')
root.mkdir(parents=True,exist_ok=True)
for name in ['alipay.png','wechat-pay.png']:(root/name).write_bytes(data)
