import { defineConfig, loadEnv } from "vite";
import path from "path";
import fs from "node:fs";
import { execFile } from "child_process";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");

  // disallow any param after `npm run dev`
  const args = process.argv.slice(4); // anything beyond `node vite --config vite.config.js`
  if (args.length !== 0) {
    console.error(
      `\n\x1b[41m\x1b[37m ERROR \x1b[0m Unknown command: '${args[0]}'. Please put '.env' arguments as prefixes to 'npm run'.`,
    );
    process.exit(1);
  }

  const courseFolder = env.COURSE || env.COURSE || "235A";
  const rootPath = `${courseFolder}/public`;
  const serverPort = Number(env.PORT || env.PORT) || 3003;
  // Loopback by default. Set HOST=0.0.0.0 to also listen on the LAN, e.g. to
  // open the notes on a phone at http://<your-lan-ip>:<port>/.
  const serverHost = env.HOST || "127.0.0.1";
  const name = `vite ${rootPath} ${serverPort}-local server`;
  const projectRoot = path.resolve(process.cwd());

  // open targets live under <course>/public; code --goto targets under <course>/wly.
  const publicRoot = path.resolve(projectRoot, rootPath);
  const wlyRoot = path.resolve(projectRoot, `${courseFolder}/wly`);
  const isInside = (base, filePath) => {
    const resolved = path.resolve(projectRoot, filePath);
    return resolved === base || resolved.startsWith(base + path.sep);
  };

  const ALLOWED_COMMANDS = {
    open: {
      pattern: /^open\s+(\S+)$/,
      executor: (match) => {
        const target = match[1].trim();
        if (!isInside(publicRoot, target)) return null;
        if (!/\.(png|jpe?g|svg)$/i.test(target)) return null;
        return { file: "open", args: [target] };
      },
    },
    code: {
      pattern: /^code\s+--goto\s+(.+):(\d+):(\d+)$/,
      executor: (match) => {
        const [, filePath, line, col] = match;
        if (!isInside(wlyRoot, filePath)) return null;
        return { file: "code", args: ["--goto", `${filePath}:${line}:${col}`] };
      },
    },
  };

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

  const validateAndSanitizeCommand = (cmd) => {
    if (!cmd || typeof cmd !== "string") {
      return null;
    }

    // Trim whitespace
    cmd = cmd.trim();

    // Check against each allowed command pattern
    for (const [commandName, config] of Object.entries(ALLOWED_COMMANDS)) {
      const match = cmd.match(config.pattern);
      if (match) {
        const sanitized = config.executor(match);
        if (sanitized) {
          console.log(`${name} validated command: ${commandName}`);
          return sanitized;
        }
      }
    }

    console.warn(`${name} rejected invalid command: ${cmd}`);
    return null;
  };

  // --- validate existence of a course ---
  if (!fs.existsSync(courseFolder)) {
    // check if the base directory even exists
    console.error(
      `\n\x1b[41m\x1b[37m ERROR \x1b[0m Course directory '\x1b[33m${courseFolder}\x1b[0m' not found.`,
    );
    process.exit(1);
  } else if (!fs.existsSync(rootPath)) {
    // base directory exists, but /public is missing
    console.error(
      `\n\x1b[41m\x1b[37m ERROR \x1b[0m Course directory '\x1b[33m${courseFolder}\x1b[0m' does not have a '\x1b[33mpublic/\x1b[0m' folder.`,
    );
    process.exit(1);
  }

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
          };
        },
      },
      {
        // Author-mode (`--local`) source-linking tooltips POST here; each
        // `cmd` is validated against ALLOWED_COMMANDS before being executed,
        // so only `open <safe-path>` and `code --goto <path:line:col>` run.
        name: name,
        configureServer(server) {
          return () => {
            server.middlewares.use((req, res, next) => {
              if (req.url !== "/log-event" || req.method !== "POST") {
                return next();
              }

              if (!isLocalRequest(req)) {
                console.error(
                  `${name} rejected non-local request (remote=${req.socket?.remoteAddress}, host=${req.headers.host}, origin=${req.headers.origin})`,
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
              req.on("end", () => {
                if (aborted) return;
                try {
                  const { cmd } = JSON.parse(body);
                  console.log(`${name} received '${cmd}'`);

                  // Validate and sanitize the command
                  const sanitizedCmd = validateAndSanitizeCommand(cmd);

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

                  execFile(
                    sanitizedCmd.file,
                    sanitizedCmd.args,
                    { cwd: process.cwd() },
                    (error) => {
                      if (error)
                        console.error(`${name} error: ${error.message}`);
                    },
                  );
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
      host: serverHost,
      cors: {
        origin: ["http://localhost:*", "http://127.0.0.1:*"],
      },
    },
  };
});
