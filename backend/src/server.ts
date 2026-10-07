import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";

const cfg = loadConfig();
const app = buildApp(cfg);

app.listen({ port: cfg.PORT, host: cfg.HOST }).then(() => {
  app.log.info(`bedoon-zahma backend listening on ${cfg.HOST}:${cfg.PORT}`);
}).catch((e) => {
  app.log.error(e);
  process.exit(1);
});

for (const sig of ["SIGINT", "SIGTERM"] as const) {
  process.on(sig, () => { app.close().finally(() => process.exit(0)); });
}
