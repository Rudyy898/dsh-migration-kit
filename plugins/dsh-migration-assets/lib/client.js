// dsh-migration-assets client half — 设置素材桥同源路径。
// pet client 读取 window.__DSH_PROXY_BRIDGE__ 拼接 /media/* URL；
// 注入同源空串后，SPRITE = "" + "/media/whale-pet.png" → 同源，走 DSH webServer 路由。
// 本文件同时用作 tapIndex 注入内容与独立 client.js（双保险）。
window.__DSH_PROXY_BRIDGE__ = window.__DSH_PROXY_BRIDGE__ || "";
