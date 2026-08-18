// dsh-migration-assets client half — 设置素材桥同源路径。
// pet client 读取 window.__DSH_PROXY_BRIDGE__ 拼接 /media/* URL；
// 注入同源空串后，SPRITE = "" + "/media/whale-pet.png" → 同源，走 DSH webServer 路由。
// 以 __ModuleLoader__ client module 形式注册（与 whale-girl 相同协议）。
window.__ModuleLoader__.load({
  id: "@dsh-migration/assets",
  factory: (require) => {
    var module = { exports: {} };
    // 尽早设置桥变量：pet client 的 apply 阶段会读它
    if (typeof window !== "undefined") {
      window.__DSH_PROXY_BRIDGE__ = window.__DSH_PROXY_BRIDGE__ || "";
    }
    var apply = function () {
      if (typeof window !== "undefined") {
        window.__DSH_PROXY_BRIDGE__ = window.__DSH_PROXY_BRIDGE__ || "";
      }
    };
    module.exports = { apply: apply };
    return module.exports;
  },
});
