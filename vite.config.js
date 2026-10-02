import { defineConfig, loadEnv } from "vite";
import path from "path";
import os from "node:os";
import crypto from "node:crypto";
import qrcode from "qrcode-terminal";
import { checkCourse } from "./scripts/dev-checks.mjs";
import { parseTooltipCommand, launchTooltip } from "./scripts/tooltip-launch.mjs";
import { validatePort } from "./scripts/dev-options.mjs";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");

  const courseFolder = env.COURSE || "235A";
  const rootPath = `${courseFolder}/public`;
  const serverPort = validatePort(env.PORT ?? "3003");
  // Loopback by default. Set HOST=0.0.0.0 to also listen on the LAN, e.g. to
  // open the notes on a phone at http://<your-lan-ip>:<port>/.
  const serverHost = env.HOST || "127.0.0.1";
  const name = `vite ${rootPath} ${serverPort}-local server`;
  const projectRoot = path.resolve(process.cwd());

  const isLoopback = (addr) =>
    addr === "127.0.0.1" || addr === "::1" || addr === "::ffff:127.0.0.1";
  const localHosts = new Set([
    `127.0.0.1:${serverPort}`,
    `localhost:${serverPort}`,
  ]);
  const localOrigins = new Set([
    `http://127.0.0.1:${serverPort}`,
    `http://localhost:${serverPort}`,
  ]);
  const isLocalRequest = (req) => {
    if (!isLoopback(req.socket?.remoteAddress)) return false;
    if (!localHosts.has(req.headers.host)) return false;
    const origin = req.headers.origin;
    if (origin && origin !== "null" && !localOrigins.has(origin)) return false;
    return true;
  };

  // A random per-startup token lets an explicitly authorized remote device (a
  // phone under `npm run dev:mobile`) drive the endpoint without opening it to
  // the whole LAN. The token is a custom header (so a malicious site can neither
  // read it nor forge the request), timing-safe compared.
  const authToken = crypto.randomBytes(24).toString("hex");
  const hasValidToken = (req) => {
    const provided = req.headers["x-author-token"];
    if (typeof provided !== "string" || provided.length !== authToken.length) {
      return false;
    }
    return crypto.timingSafeEqual(Buffer.from(provided), Buffer.from(authToken));
  };

  checkCourse(projectRoot, courseFolder);

  return {
    root: rootPath,
    plugins: [
      {
        name: "server-log-customizer",
        configureServer(server) {
          const _print = server.printUrls;
          server.printUrls = () => {
            console.log(
              `  \x1b[32m➜\x1b[0m  \x1b[1mServing:\x1b[0m \x1b[36m${rootPath}\x1b[0m`,
            );
            _print();
            // Only relevant when listening on the LAN (npm run dev:mobile).
            if (serverHost !== "127.0.0.1" && serverHost !== "localhost") {
              const lanIp = Object.values(os.networkInterfaces())
                .flat()
                .find(
                  (i) =>
                    i && !i.internal && (i.family === "IPv4" || i.family === 4),
                )?.address;
              const base = lanIp
                ? `http://${lanIp}:${serverPort}`
                : `http://<lan-ip>:${serverPort}`;
              const authUrl = `${base}/#authToken=${authToken}`;
              console.log(
                `\n  \x1b[33m🔑 Author tooltips on mobile\x1b[0m — scan once on the device:`,
              );
              if (lanIp) {
                qrcode.generate(authUrl, { small: true }, (qr) =>
                  console.log(qr),
                );
              }
              console.log(`     or open: \x1b[36m${authUrl}\x1b[0m\n`);
            }
          };
        },
      },
      {
        // Author-mode (`--local`) source-linking tooltips POST here; each
        // `cmd` is validated by parseTooltipCommand before being executed,
        // so only `open <safe-path>` and `code --goto <path:line:col>` run.
        name: name,
        configureServer(server) {
          return () => {
            server.middlewares.use((req, res, next) => {
              if (req.url !== "/log-event" || req.method !== "POST") {
                return next();
              }

              if (!isLocalRequest(req) && !hasValidToken(req)) {
                console.error(
                  `${name} rejected unauthorized request (remote=${req.socket?.remoteAddress}, host=${req.headers.host}, origin=${req.headers.origin})`,
                );
                res.writeHead(403, { "Content-Type": "application/json" });
                res.end(JSON.stringify({ success: false, error: "Forbidden" }));
                return;
              }

              let body = "";
              let aborted = false;
              const MAX_BODY = 8 * 1024;
              req.on("data", (chunk) => {
                if (aborted) return;
                body += chunk;
                if (body.length > MAX_BODY) {
                  aborted = true;
                  res.writeHead(413, { "Content-Type": "application/json" });
                  res.end(
                    JSON.stringify({
                      success: false,
                      error: "Payload too large",
                    }),
                  );
                  req.destroy();
                }
              });
              req.on("end", async () => {
                if (aborted) return;
                try {
                  const { cmd } = JSON.parse(body);
                  console.log(`${name} received '${cmd}'`);

                  // Validate and sanitize the command
                  const sanitizedCmd = parseTooltipCommand(cmd, projectRoot, courseFolder);

                  if (!sanitizedCmd) {
                    console.error(`${name} rejected command: ${cmd}`);
                    res.writeHead(403, { "Content-Type": "application/json" });
                    res.end(
                      JSON.stringify({
                        success: false,
                        error: "Command not allowed",
                      }),
                    );
                    return;
                  }

                  const result = await launchTooltip(sanitizedCmd, { cwd: projectRoot });
                  if (!result.success) console.error(`${name}: ${result.error}`);
                  res.writeHead(result.status, { "Content-Type": "application/json" });
                  res.end(JSON.stringify({ success: result.success, error: result.error }));
                } catch (e) {
                  console.error(`${name} parse error:`, e);
                  res.writeHead(400, { "Content-Type": "application/json" });
                  res.end(JSON.stringify({ success: false, error: "Invalid tooltip request" }));
                }
              });
            });
          };
        },
      },
    ],
    server: {
      port: serverPort,
      strictPort: true,
      host: serverHost,
      cors: {
        origin: ["http://localhost:*", "http://127.0.0.1:*"],
      },
    },
  };
});
