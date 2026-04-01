import { defineConfig, loadEnv } from "vite";
import fs from "node:fs";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");

  const courseFolder = env.COURSE || "235A";
  const rootPath = `${courseFolder}/public`;
  const serverPort = Number(env.PORT) || 3003;

  // --- validate existence of a course ---
  // check if the directory exists and is a directory
  if (!fs.existsSync(rootPath)) {
    console.error(
      `\n\x1b[41m\x1b[37m ERROR \x1b[0m Course directory not found: \x1b[33m${rootPath}\x1b[0m`,
    );
    console.error(
      `Please check your environment variable. COURSE=${courseFolder} does not contain a /public folder.\n`,
    );
    process.exit(1); // refuse to start the server
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
              `\n  \x1b[32m➜\x1b[0m  \x1b[1mServing Course:\x1b[0m \x1b[36m${courseFolder}\x1b[0m`,
            );
            console.log(
              `  \x1b[32m➜\x1b[0m  \x1b[1mRoot Path:\x1b[0m      \x1b[36m${rootPath}\x1b[0m`,
            );
            _print();
          };
        },
      },
      {
        name: "mathjax-injector",
        transformIndexHtml(html) {
          const version = (env.MATHJAX_VERSION || "3").trim();
          const offline = (env.OFFLINE_MODE || "false").toLowerCase().trim();

          const version_offline = `${version}-${offline}`;

          const mathjax_url = () => {
            switch (version_offline) {
              case "3-true":
                return "./mathjax3/tex-svg.js";
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

          // inject MathJax script between mathjax_setup.js and app.js
          return html.replace(
            /(<script[^>]+src="\.\/mathjax_setup\.js"><\/script>)/,
            `$1\n<script type="text/javascript" id="mathjax-script" src="${mathjax_url()}"></script>`,
          );
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
