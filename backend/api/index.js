// مُهايئ Vercel Serverless: يمرّر طلبات Node إلى تطبيق Fastify المبني في dist/.
// يُبنى بـ `npm run build` (buildCommand في vercel.json) ثم يُستدعى لكل طلب.
import { buildApp } from "../dist/app.js";
import { loadConfig } from "../dist/config.js";

let appPromise;
function getApp() {
  if (!appPromise) {
    const app = buildApp(loadConfig());
    appPromise = app.ready().then(() => app);
  }
  return appPromise;
}

export default async function handler(req, res) {
  const app = await getApp();
  app.server.emit("request", req, res);
}
